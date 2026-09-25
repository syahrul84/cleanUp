import SwiftUI

struct DuplicatesView: View {
    @State private var groups: [DuplicateGroup] = []
    @State private var scanning = false
    @State private var hasScanned = false
    @State private var progress = 0.0
    @State private var progressText = "Starting…"

    private var selectedItems: [RemovalItem] {
        groups.flatMap(\.files).filter(\.selected)
    }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var wasted: Int64 { groups.reduce(0) { $0 + $1.wastedSize } }

    var body: some View {
        Group {
            if groups.isEmpty {
                ScanHero(icon: "doc.on.doc",
                         title: "Duplicate Finder",
                         description: "Finds exact duplicate files in the folders you choose — compared by content, so there are no false matches.\nNothing is removed without your confirmation.",
                         buttonTitle: "Choose Folders…",
                         buttonIcon: "folder.badge.plus",
                         scanning: scanning,
                         progressText: progressText,
                         progress: progress,
                         resultNote: hasScanned ? "No duplicates found." : nil) { chooseAndScan() }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            SummaryCard(icon: "doc.on.doc", tint: .teal,
                                        title: "\(Format.bytes(wasted)) wasted on \(groups.count) duplicate\(groups.count == 1 ? "" : "s")",
                                        subtitle: "\(selectedItems.count) extra copies selected · \(Format.bytes(selectedSize)) will move to the Trash · the first copy of each is kept")
                            ForEach($groups) { $group in
                                groupCard($group)
                            }
                        }
                        .padding(16)
                    }
                    ResultsActionBar(rescanTitle: "Choose Folders…", rescanIcon: "folder.badge.plus",
                                     scanning: scanning, rescan: chooseAndScan) {
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
            }
        }
        .navigationTitle("Duplicate Finder")
        .navigationSubtitle(groups.isEmpty ? "" : "\(groups.count) groups — \(Format.bytes(wasted)) wasted")
    }

    private func groupCard(_ group: Binding<DuplicateGroup>) -> some View {
        let g = group.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: g.files.first?.url.path ?? ""))
                    .resizable().interpolation(.high)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.files.first?.url.lastPathComponent ?? "Duplicate")
                        .font(.headline).lineLimit(1).truncationMode(.middle)
                    Text("\(g.files.count) identical copies · \(Format.bytes(g.fileSize)) each")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.bytes(g.wastedSize)).font(.callout.bold()).monospacedDigit()
                    Text("wasted").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
            Divider().padding(.vertical, 2)
            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, $file in
                FileRow(item: $file,
                        detail: file.label,
                        trailingNote: file.selected ? "remove" : "keep")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chooseAndScan() {
        let roots = FolderPicker.choose(prompt: "Scan")
        if !roots.isEmpty { scan(roots: roots) }
    }

    private func scan(roots: [URL]) {
        scanning = true
        hasScanned = false
        groups = []
        progress = 0
        progressText = "Starting…"
        let reporter = ScanProgressReporter { fraction, text in
            progress = fraction
            progressText = text
        }
        Task.detached(priority: .userInitiated) {
            let found = DuplicateScanner.scan(roots: roots, progress: reporter)
            await MainActor.run {
                groups = found
                scanning = false
                hasScanned = true
            }
        }
    }
}
