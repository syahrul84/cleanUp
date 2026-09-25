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
        ScrollView {
            VStack(spacing: 14) {
                healthGrid
                HStack(alignment: .top, spacing: 14) {
                    processCard(title: "Top CPU", icon: "cpu", tint: .blue,
                                procs: topCPU,
                                emptyText: "Nothing is using significant CPU.",
                                value: { String(format: "%.0f%%", $0.cpuPercent) },
                                fraction: { $0.cpuPercent / max(topCPU.first?.cpuPercent ?? 1, 1) })
                    processCard(title: "Top Memory", icon: "memorychip", tint: .orange,
                                procs: topMem,
                                emptyText: "Reading memory usage…",
                                value: { Format.bytes($0.memBytes) },
                                fraction: { Double($0.memBytes) / Double(max(topMem.first?.memBytes ?? 1, 1)) })
                }
                if !sleepBlockers.isEmpty {
                    HStack(spacing: 8) {
                        IconTile(systemName: "moon.zzz", tint: .indigo, size: 24)
                        Text("Preventing sleep: \(sleepBlockers.joined(separator: ", "))")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
                tweaksCard
                maintenanceCard
            }
            .padding(16)
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

    private var healthGrid: some View {
        Group {
            if checks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking your Mac's health…").foregroundStyle(.secondary)
                }
                .frame(height: 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible())], spacing: 12) {
                    ForEach(checks) { check in
                        StatCard(icon: check.icon,
                                 tint: Color(nsColor: check.status.color),
                                 title: check.title,
                                 value: check.value,
                                 caption: check.detail,
                                 actionLabel: check.goTo != nil ? check.actionLabel : nil,
                                 height: 118) {
                            if let target = check.goTo { AppState.shared.open(target) }
                        }
                    }
                }
            }
        }
    }

    private func processCard(title: String, icon: String, tint: Color,
                             procs: [ProcInfo], emptyText: String,
                             value: @escaping (ProcInfo) -> String,
                             fraction: @escaping (ProcInfo) -> Double) -> some View {
        SectionCard(title: title, icon: icon, tint: tint,
                    info: "Live, refreshed every 3 seconds. Quit asks politely — an app with unsaved work can refuse.") {
            if procs.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            ForEach(procs) { proc in
                HoverRow {
                    processIcon(proc)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(proc.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(value(proc)).font(.callout).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        UsageBar(fraction: fraction(proc), tint: tint)
                    }
                    HoverIconButton(systemName: "xmark", help: "Quit \(proc.name)") {
                        if let error = SpeedService.quit(proc) { message = error }
                        refreshHogs()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func processIcon(_ proc: ProcInfo) -> some View {
        if let icon = ProcessIcons.icon(for: proc.id) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 24, height: 24)
        } else {
            IconTile(systemName: "gearshape", tint: .gray, size: 24)
        }
    }

    private static let tweakIcons: [String: String] = [
        "dock-delay": "dock.rectangle",
        "mission-control": "rectangle.3.group",
        "window-anim": "macwindow",
        "resize-time": "arrow.up.left.and.arrow.down.right",
    ]

    private var tweaksCard: some View {
        SectionCard(title: "Snappiness", icon: "hare", tint: .orange,
                    info: "These shorten or skip interface animations — your Mac feels quicker because it stops making you wait. They don't add computing power, and every one is reversible.",
                    accessory: AnyView(
                        Button("Restore Defaults") {
                            SpeedService.restoreAllTweaks()
                            refreshTweaks()
                        }
                        .controlSize(.small))) {
            ForEach(SpeedService.tweaks) { tweak in
                HoverRow {
                    IconTile(systemName: Self.tweakIcons[tweak.id] ?? "sparkles", tint: .orange)
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
            }
        }
    }

    private var maintenanceCard: some View {
        SectionCard(title: "Maintenance", icon: "wrench.and.screwdriver", tint: .teal) {
            maintenanceRow("Flush DNS cache", "Fixes many “internet is slow / site won’t load” issues. Asks for your admin password.",
                           icon: "network", tint: .blue) {
                Task.detached {
                    let error = SpeedService.flushDNS()
                    await MainActor.run { message = error ?? "DNS cache flushed." }
                }
            }
            maintenanceRow("Restart Finder", "Fixes a laggy or frozen desktop and file windows.",
                           icon: "folder", tint: .cyan) {
                SpeedService.restartFinder()
                message = "Finder restarted."
            }
            maintenanceRow("Restart Dock", "Fixes a stuck Dock, Mission Control or Stage Manager.",
                           icon: "dock.rectangle", tint: .indigo) {
                SpeedService.restartDock()
                message = "Dock restarted."
            }
            if SpeedService.hasSimulators {
                maintenanceRow("Remove unavailable simulators", "Deletes simulators for OS versions you no longer have — often several GB.",
                               icon: "iphone", tint: .green) {
                    Task.detached {
                        let error = SpeedService.removeUnavailableSimulators()
                        await MainActor.run {
                            message = error ?? "Unavailable simulators removed."
                        }
                    }
                }
            }
            maintenanceRow("Re-index a folder in Spotlight…", "Re-imports a folder whose contents don’t show up in search.",
                           icon: "magnifyingglass", tint: .yellow) {
                if let folder = FolderPicker.choose(prompt: "Re-index").first {
                    Task.detached {
                        let error = SpeedService.reindex(folder: folder)
                        await MainActor.run {
                            message = error ?? "Re-import of “\(folder.lastPathComponent)” started."
                        }
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func maintenanceRow(_ title: String, _ detail: String,
                                icon: String, tint: Color,
                                action: @escaping () -> Void) -> some View {
        HoverRow {
            IconTile(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Run", action: action)
        }
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
