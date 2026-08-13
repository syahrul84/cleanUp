import SwiftUI

struct JunkView: View {
    @State private var categories: [JunkCategory] = []
    @State private var scanning = false
    @State private var hasScanned = false

    private var selectedItems: [RemovalItem] {
        categories.flatMap(\.items).filter(\.selected)
    }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        Group {
            if categories.isEmpty {
                ScanPlaceholder(scanning: scanning,
                                emptyIcon: "sparkles",
                                emptyText: hasScanned ? "No junk found — nice and clean!"
                                                      : "Scan to find caches, logs and other junk.")
            } else {
                List {
                    ForEach($categories) { $category in
                        Section {
                            DisclosureGroup {
                                ForEach($category.items) { $item in
                                    RemovalRow(item: $item)
                                }
                            } label: {
                                HStack {
                                    Label(category.kind.rawValue, systemImage: category.kind.systemImage)
                                    Spacer()
                                    Text(Format.bytes(category.totalSize))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                        } footer: {
                            Text(category.kind.explanation)
                                .font(.caption).foregroundStyle(.tertiary)
                        }
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
                TrashActionButton(count: selectedItems.count, size: selectedSize) {
                    let result = FileUtils.trash(selectedItems.map(\.url))
                    return result
                } onDone: { scan() }
            }
        }
        .navigationTitle("Junk Cleaner")
        .navigationSubtitle(categories.isEmpty ? "" :
            "Reclaimable: \(Format.bytes(categories.reduce(0) { $0 + $1.totalSize }))")
    }

    private func scan() {
        scanning = true
        categories = []
        Task.detached(priority: .userInitiated) {
            let result = JunkScanner.scan()
            await MainActor.run {
                categories = result
                scanning = false
                hasScanned = true
            }
        }
    }
}
