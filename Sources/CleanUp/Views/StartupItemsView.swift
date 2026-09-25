import SwiftUI

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var scanning = false
    @State private var errorMessage: String?

    private func items(in scope: StartupItem.Scope) -> [StartupItem] {
        items.filter { $0.scope == scope }
    }

    private var activeUserAgents: Int { items.filter { $0.scope == .userAgent && $0.enabled }.count }
    private var disabledUserAgents: Int { items.filter { $0.scope == .userAgent && !$0.enabled }.count }

    var body: some View {
        Group {
            if items.isEmpty {
                ScanHero(icon: "power",
                         title: "Startup Items",
                         description: "Shows everything that launches automatically when you log in or start your Mac, and lets you switch off your own launch agents.",
                         buttonTitle: "Find Startup Items",
                         scanning: scanning,
                         progressText: "Reading launch agents and daemons…") { scan() }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        summary
                        scopeCard(.userAgent,
                                  title: "Your Launch Agents", icon: "person.crop.circle", tint: .teal,
                                  info: "Background helpers installed for your account. Switching one off unloads it and moves its file to “LaunchAgents (Disabled)” — switch it back on anytime.")
                        scopeCard(.systemAgent,
                                  title: "System-wide Launch Agents", icon: "person.2.circle", tint: .blue,
                                  info: "Helpers that run for every user. Changing these needs admin rights, so they're shown for information. Right-click any item to reveal it in Finder.")
                        scopeCard(.systemDaemon,
                                  title: "Launch Daemons", icon: "gearshape.2", tint: .indigo,
                                  info: "System services that start before anyone logs in. Changing these needs admin rights, so they're shown for information. Right-click any item to reveal it in Finder.")
                    }
                    .padding(16)
                }
            }
        }
        .alert("Startup item error", isPresented: .init(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationTitle("Startup Items")
        .navigationSubtitle(items.isEmpty ? "" : "\(items.count) items")
        .onAppear { if items.isEmpty && !scanning { scan() } }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "power", tint: .teal, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.count) startup item\(items.count == 1 ? "" : "s")").font(.headline)
                Text("\(activeUserAgents) active user agent\(activeUserAgents == 1 ? "" : "s") · \(disabledUserAgents) disabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Login Items…", systemImage: "arrow.up.forward.app") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
            .help("Apps that open at login are managed in System Settings")
            Button("Refresh", systemImage: "arrow.clockwise") { scan() }
                .disabled(scanning)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func scopeCard(_ scope: StartupItem.Scope, title: String, icon: String,
                           tint: Color, info: String) -> some View {
        let scoped = items(in: scope)
        if !scoped.isEmpty {
            SectionCard(title: "\(title) (\(scoped.count))", icon: icon, tint: tint, info: info) {
                ForEach(scoped) { item in
                    row(item)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: StartupItem) -> some View {
        let appName = ProcessIcons.appName(containing: item.program)
        HoverRow {
            if let icon = ProcessIcons.appIcon(containing: item.program) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28)
            } else {
                IconTile(systemName: "terminal", tint: .gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(appName ?? item.label).lineLimit(1)
                Text(appName == nil ? (item.program as NSString).lastPathComponent : item.label)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .help(item.program)
            Spacer()
            if item.scope == .userAgent {
                Text(item.enabled ? "On" : "Off")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("", isOn: Binding(
                    get: { item.enabled },
                    set: { _ in toggle(item) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            } else {
                Label("Admin", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .help("Needs admin rights to change")
            }
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private func toggle(_ item: StartupItem) {
        errorMessage = item.enabled ? StartupScanner.disable(item) : StartupScanner.enable(item)
        scan()
    }

    private func scan() {
        scanning = true
        Task.detached(priority: .userInitiated) {
            let found = StartupScanner.scan()
            await MainActor.run { items = found; scanning = false }
        }
    }
}
