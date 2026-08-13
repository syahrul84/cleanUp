import SwiftUI

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var scanning = false
    @State private var errorMessage: String?

    private var grouped: [(scope: StartupItem.Scope, items: [StartupItem])] {
        let scopes: [StartupItem.Scope] = [.userAgent, .systemAgent, .systemDaemon]
        return scopes.compactMap { scope in
            let scoped = items.filter { $0.scope == scope }
            return scoped.isEmpty ? nil : (scope, scoped)
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ScanPlaceholder(scanning: scanning, emptyIcon: "power",
                                emptyText: "Scan to list launch agents and daemons.")
            } else {
                List {
                    ForEach(grouped, id: \.scope) { group in
                        Section {
                            ForEach(group.items) { item in
                                row(item)
                            }
                        } header: {
                            Text(group.scope.rawValue)
                        } footer: {
                            if group.scope == .userAgent {
                                Text("Toggling off moves the item to “LaunchAgents (Disabled)” and unloads it — fully reversible.")
                                    .font(.caption).foregroundStyle(.tertiary)
                            } else {
                                Text("System-level items need admin rights — shown for information. Right-click to reveal in Finder.")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Section {
                        Button("Manage Login Items in System Settings…") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }
                    } footer: {
                        Text("Apps that open at login are managed by macOS itself.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(scanning ? "Scanning…" : "Scan", systemImage: "arrow.clockwise") { scan() }
                    .disabled(scanning)
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

    @ViewBuilder
    private func row(_ item: StartupItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Text(item.program).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if item.scope == .userAgent {
                Toggle("", isOn: Binding(
                    get: { item.enabled },
                    set: { _ in toggle(item) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            } else {
                Text("Requires admin").font(.caption).foregroundStyle(.tertiary)
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
