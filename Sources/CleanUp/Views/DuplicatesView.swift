import SwiftUI

struct DuplicatesView: View {
    @State private var groups: [DuplicateGroup] = []
    @State private var scanning = false
    @State private var hasScanned = false
    @State private var progressText = "Scanning…"

    private var selectedItems: [RemovalItem] {
        groups.flatMap(\.files).filter(\.selected)
    }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        Group {
            if groups.isEmpty {
                ScanPlaceholder(scanning: scanning, emptyIcon: "doc.on.doc",
                                emptyText: hasScanned ? "No duplicates found."
                                                      : "Choose folders to scan for exact duplicates.",
                                progressText: progressText)
            } else {
                List {
                    ForEach($groups) { $group in
                        Section("\(group.files.count)× \(group.files.first?.url.lastPathComponent ?? "") — wasted \(Format.bytes(group.wastedSize))") {
                            ForEach($group.files) { $file in
                                RemovalRow(item: $file, showPath: true)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Choose Folders…", systemImage: "folder.badge.plus") {
                    let roots = FolderPicker.choose(prompt: "Scan")
                    if !roots.isEmpty { scan(roots: roots) }
                }
                .disabled(scanning)
            }
            ToolbarItem(placement: .primaryAction) {
                TrashActionButton(count: selectedItems.count, size: selectedSize,
                                  urls: { selectedItems.map(\.url) }) {
                    // Remove trashed files from the display; drop groups with <2 remaining.
                    for i in groups.indices {
                        groups[i].files.removeAll(where: \.selected)
                    }
                    groups.removeAll { $0.files.count < 2 }
                }
            }
        }
        .navigationTitle("Duplicate Finder")
        .navigationSubtitle(groups.isEmpty ? "" :
            "\(groups.count) groups — \(Format.bytes(groups.reduce(0) { $0 + $1.wastedSize })) wasted")
    }

    private func scan(roots: [URL]) {
        scanning = true
        hasScanned = false
        groups = []
        Task.detached(priority: .userInitiated) {
            let found = DuplicateScanner.scan(roots: roots) { text in
                Task { @MainActor in progressText = text }
            }
            await MainActor.run {
                groups = found
                scanning = false
                hasScanned = true
            }
        }
    }
}
