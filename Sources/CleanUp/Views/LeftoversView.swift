import SwiftUI

struct LeftoversView: View {
    @State private var items: [RemovalItem] = []
    @State private var scanning = false
    @State private var hasScanned = false

    private var selected: [RemovalItem] { items.filter(\.selected) }
    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    var body: some View {
        Group {
            if items.isEmpty {
                ScanPlaceholder(scanning: scanning, emptyIcon: "magnifyingglass",
                                emptyText: hasScanned ? "No orphaned files found."
                                                      : "Scan ~/Library for files left behind by deleted apps.")
            } else {
                List {
                    Section {
                        ForEach($items) { $item in
                            RemovalRow(item: $item, showPath: true)
                        }
                    } header: {
                        Text("Files whose app no longer appears to be installed")
                    } footer: {
                        Text("Review before removing: files from menu-bar tools, CLI tools or plug-ins can look orphaned. Nothing is selected by default.")
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
            ToolbarItem(placement: .primaryAction) {
                TrashActionButton(count: selected.count, size: selectedSize) {
                    let result = FileUtils.trash(selected.map(\.url))
                    return result
                } onDone: { items.removeAll(where: \.selected) }
            }
        }
        .navigationTitle("Leftover Finder")
        .navigationSubtitle(items.isEmpty ? "" :
            "\(items.count) orphaned items — \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
    }

    private func scan() {
        scanning = true
        items = []
        Task.detached(priority: .userInitiated) {
            let apps = AppScanner.installedApps()
            let ids = AppScanner.installedBundleIDs(apps)
            let found = LeftoverScanner.orphans(installedBundleIDs: ids)
            await MainActor.run {
                items = found
                scanning = false
                hasScanned = true
            }
        }
    }
}
