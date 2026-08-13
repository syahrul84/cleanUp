import SwiftUI

struct LargeFilesView: View {
    @State private var files: [LargeFile] = []
    @State private var scanning = false
    @State private var hasScanned = false

    private var selected: [LargeFile] { files.filter(\.selected) }
    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    var body: some View {
        Group {
            if files.isEmpty {
                ScanPlaceholder(scanning: scanning, emptyIcon: "externaldrive.badge.exclamationmark",
                                emptyText: hasScanned ? "No files over 50 MB found."
                                                      : "Choose folders to find large files (over 50 MB).")
            } else {
                Table(of: Binding<LargeFile>.self) {
                    TableColumn("") { $file in
                        Toggle("", isOn: $file.selected).labelsHidden()
                    }
                    .width(28)
                    TableColumn("Name") { $file in
                        Text(file.url.lastPathComponent).lineLimit(1)
                            .help(file.url.path)
                    }
                    TableColumn("Size") { $file in
                        Text(Format.bytes(file.size)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Last opened") { $file in
                        Text(file.lastAccess.map {
                            $0.formatted(date: .abbreviated, time: .omitted)
                        } ?? "—").foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("Location") { $file in
                        Text(file.url.deletingLastPathComponent().path
                            .replacingOccurrences(of: FileUtils.home.path, with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                } rows: {
                    ForEach($files) { $file in
                        TableRow($file)
                    }
                }
                .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
                    Button("Show in Finder") {
                        let urls = files.filter { ids.contains($0.id) }.map(\.url)
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
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
                TrashActionButton(count: selected.count, size: selectedSize) {
                    let result = FileUtils.trash(selected.map(\.url))
                    return result
                } onDone: { files.removeAll(where: \.selected) }
            }
        }
        .navigationTitle("Large & Old Files")
        .navigationSubtitle(files.isEmpty ? "" :
            "\(files.count) files — \(Format.bytes(files.reduce(0) { $0 + $1.size }))")
    }

    private func scan(roots: [URL]) {
        scanning = true
        hasScanned = false
        files = []
        Task.detached(priority: .userInitiated) {
            let found = LargeFilesScanner.scan(roots: roots)
            await MainActor.run {
                files = found
                scanning = false
                hasScanned = true
            }
        }
    }
}
