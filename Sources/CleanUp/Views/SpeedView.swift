import SwiftUI

struct SpeedView: View {
    @State private var checks: [HealthCheck] = []
    @State private var topCPU: [ProcInfo] = []
    @State private var topMem: [ProcInfo] = []
    @State private var sleepBlockers: [String] = []
    @State private var tweakStates: [String: Bool] = [:]
    @State private var message: String?
    @State private var refreshTimer: Timer?

    var body: some View {
        List {
            healthSection
            hogsSection
            tweaksSection
            maintenanceSection
        }
        .navigationTitle("Speed")
        .alert("Speed", isPresented: .init(
            get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear { start() }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: Sections

    private var healthSection: some View {
        Section("Health check") {
            if checks.isEmpty {
                HStack { ProgressView(); Text("Checking…").foregroundStyle(.secondary) }
            }
            ForEach(checks) { check in
                HStack(spacing: 10) {
                    Image(systemName: check.icon).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: check.status.color)).frame(width: 8, height: 8)
                            Text(check.title)
                        }
                        Text(check.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let target = check.goTo {
                        Button("Fix…") { AppState.shared.open(target) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var hogsSection: some View {
        Group {
            Section("Top CPU right now") {
                if topCPU.isEmpty {
                    Text("Nothing is using significant CPU.").foregroundStyle(.secondary)
                }
                ForEach(topCPU) { proc in procRow(proc, value: String(format: "%.0f%%", proc.cpuPercent)) }
            }
            Section {
                ForEach(topMem) { proc in procRow(proc, value: Format.bytes(proc.memBytes)) }
                if !sleepBlockers.isEmpty {
                    Label("Preventing sleep: \(sleepBlockers.joined(separator: ", "))",
                          systemImage: "moon.zzz")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Top memory")
            } footer: {
                Text("Quit is polite — apps with unsaved work can refuse. Updates every 3 seconds.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var tweaksSection: some View {
        Section {
            ForEach(SpeedService.tweaks) { tweak in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tweak.title)
                        Text(tweak.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { tweakStates[tweak.id] ?? false },
                        set: { on in
                            tweak.set(on)
                            tweakStates[tweak.id] = tweak.isOn()
                        }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
                .padding(.vertical, 2)
            }
            Button("Restore macOS defaults") {
                SpeedService.restoreAllTweaks()
                refreshTweaks()
            }
        } header: {
            Text("Snappiness")
        } footer: {
            Text("These shorten or skip interface animations — the Mac feels quicker because it stops making you wait. They do not add computing power. All reversible.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var maintenanceSection: some View {
        Section {
            maintenanceRow("Flush DNS cache", "Fixes many “internet is slow / site won’t load” issues. Asks for your admin password.") {
                Task.detached {
                    let error = SpeedService.flushDNS()
                    await MainActor.run { message = error ?? "DNS cache flushed." }
                }
            }
            maintenanceRow("Restart Finder", "Fixes a laggy or frozen desktop and file windows.") {
                SpeedService.restartFinder()
                message = "Finder restarted."
            }
            maintenanceRow("Restart Dock", "Fixes a stuck Dock, Mission Control or Stage Manager.") {
                SpeedService.restartDock()
                message = "Dock restarted."
            }
            maintenanceRow("Re-index a folder in Spotlight…", "Re-imports a folder whose contents don’t show up in search.") {
                if let folder = FolderPicker.choose(prompt: "Re-index").first {
                    Task.detached {
                        let error = SpeedService.reindex(folder: folder)
                        await MainActor.run {
                            message = error ?? "Re-import of “\(folder.lastPathComponent)” started."
                        }
                    }
                }
            }
        } header: {
            Text("Maintenance")
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func procRow(_ proc: ProcInfo, value: String) -> some View {
        HStack {
            if let icon = proc.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "gearshape").frame(width: 20)
            }
            Text(proc.name).lineLimit(1)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
            Button("Quit") {
                if let error = SpeedService.quit(proc) { message = error }
                refreshHogs()
            }
            .controlSize(.small)
        }
    }

    private func maintenanceRow(_ title: String, _ detail: String,
                                action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Run") { action() }
        }
        .padding(.vertical, 2)
    }

    // MARK: Data

    private func start() {
        refreshTweaks()
        refreshHealth()
        refreshHogs()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            refreshHogs()
        }
    }

    private func refreshHealth() {
        Task.detached(priority: .userInitiated) {
            let result = SpeedService.healthChecks()
            await MainActor.run { checks = result }
        }
    }

    private func refreshHogs() {
        Task.detached(priority: .utility) {
            let (cpu, mem) = SpeedService.topProcesses()
            let blockers = SpeedService.sleepBlockers()
            await MainActor.run {
                topCPU = cpu
                topMem = mem
                sleepBlockers = blockers
            }
        }
    }

    private func refreshTweaks() {
        Task.detached(priority: .utility) {
            let states = Dictionary(uniqueKeysWithValues: SpeedService.tweaks.map { ($0.id, $0.isOn()) })
            await MainActor.run { tweakStates = states }
        }
    }
}
