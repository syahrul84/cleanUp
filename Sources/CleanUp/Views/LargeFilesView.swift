import SwiftUI

struct LargeFilesView: View {
    @State private var files: [LargeFile] = []
    @State private var scanning = false
    @State private var hasScanned = false
    @State private var progress = 0.0
    @State private var progressText = "Starting…"

    private var selected: [LargeFile] { files.filter(\.selected) }
    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }
    private var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    var body: some View {
        Group {
            if files.isEmpty {
                ScanHero(icon: "externaldrive.badge.exclamationmark",
                         title: "Large & Old Files",
                         description: "Finds files over 50 MB in the folders you choose, with when you last opened them.\nNothing is removed without your confirmation.",
                         buttonTitle: "Choose Folders…",
                         buttonIcon: "folder.badge.plus",
                         scanning: scanning,
                         progressText: progressText,
                         progress: progress,
                         resultNote: hasScanned ? "No files over 50 MB found." : nil) { chooseAndScan() }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            SummaryCard(icon: "externaldrive.badge.exclamationmark", tint: .indigo,
                                        title: "\(files.count) large files · \(Format.bytes(totalSize))",
                                        subtitle: "\(selected.count) selected · \(Format.bytes(selectedSize)) will move to the Trash")
                            SectionCard(title: "Largest first", icon: "arrow.down.circle", tint: .indigo,
                                        info: "Files over 50 MB, biggest at the top. The date shows when each file was last opened — old, big files you've forgotten are usually the safest wins. Click a row to select it; right-click to reveal it in Finder.") {
                                ForEach($files) { $file in
                                    row($file)
                                }
                            }
                        }
                        .padding(16)
                    }
                    ResultsActionBar(rescanTitle: "Choose Folders…", rescanIcon: "folder.badge.plus",
                                     scanning: scanning, rescan: chooseAndScan) {
                        TrashActionButton(count: selected.count, size: selectedSize,
                                          urls: { selected.map(\.url) }) {
                            files.removeAll(where: \.selected)
                        }
                    }
                }
            }
        }
        .navigationTitle("Large & Old Files")
        .navigationSubtitle(files.isEmpty ? "" : "\(files.count) files — \(Format.bytes(totalSize))")
    }

    private func row(_ file: Binding<LargeFile>) -> some View {
        let f = file.wrappedValue
        let stale = f.lastAccess.map { Date().timeIntervalSince($0) > 180 * 86_400 } ?? true
        return HoverRow(highlight: .accentColor) {
            Toggle("", isOn: file.selected).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path))
                .resizable().interpolation(.high)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(f.url.deletingLastPathComponent().path
                        .replacingOccurrences(of: FileUtils.home.path, with: "~"))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(f.size)).font(.callout).monospacedDigit()
                Label(f.lastAccess.map { "Opened " + $0.formatted(.relative(presentation: .named)) }
                        ?? "Never opened",
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        }
        .onTapGesture { file.wrappedValue.selected.toggle() }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([f.url])
            }
        }
    }

    private func chooseAndScan() {
        let roots = FolderPicker.choose(prompt: "Scan")
        if !roots.isEmpty { scan(roots: roots) }
    }

    private func scan(roots: [URL]) {
        scanning = true
        hasScanned = false
        files = []
        progress = 0
        progressText = "Starting…"
        let reporter = ScanProgressReporter { fraction, text in
            progress = fraction
            progressText = text
        }
        Task.detached(priority: .userInitiated) {
            let found = LargeFilesScanner.scan(roots: roots, progress: reporter)
            await MainActor.run {
                files = found
                scanning = false
                hasScanned = true
            }
        }
    }
}
