import SwiftUI

struct LeftoversView: View {
    @State private var items: [RemovalItem] = []
    @State private var scanning = false
    @State private var hasScanned = false
    @State private var progress = 0.0
    @State private var progressText = "Starting…"

    private var selected: [RemovalItem] { items.filter(\.selected) }
    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }
    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        Group {
            if items.isEmpty {
                ScanHero(icon: "magnifyingglass",
                         title: "Leftover Finder",
                         description: "Finds files in your Library left behind by apps you've already deleted.\nNothing is selected or removed without your confirmation.",
                         buttonTitle: hasScanned ? "Scan Again" : "Start Scan",
                         scanning: scanning,
                         progressText: progressText,
                         progress: progress,
                         resultNote: hasScanned ? "No orphaned files found." : nil) { scan() }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            SummaryCard(icon: "magnifyingglass", tint: .orange,
                                        title: "\(items.count) leftover item\(items.count == 1 ? "" : "s") · \(Format.bytes(totalSize))",
                                        subtitle: "\(selected.count) selected · \(Format.bytes(selectedSize)) will move to the Trash")
                            SectionCard(title: "From apps that no longer seem installed", icon: "questionmark.folder", tint: .orange,
                                        info: "These files are named after apps CleanUp can't find on your Mac. Review before removing — files from menu-bar tools, command-line tools or plug-ins can look orphaned. Nothing is selected by default.",
                                        accessory: AnyView(SelectAllBox(items: $items))) {
                                ForEach($items) { $item in
                                    FileRow(item: $item,
                                            detail: "\(item.label) · \(item.url.deletingLastPathComponent().path.replacingOccurrences(of: FileUtils.home.path, with: "~"))")
                                }
                            }
                        }
                        .padding(16)
                    }
                    ResultsActionBar(rescanTitle: "Scan Again", scanning: scanning, rescan: scan) {
                        TrashActionButton(count: selected.count, size: selectedSize,
                                          urls: { selected.map(\.url) }) {
                            items.removeAll(where: \.selected)
                        }
                    }
                }
            }
        }
        .navigationTitle("Leftover Finder")
        .navigationSubtitle(items.isEmpty ? "" : "\(items.count) orphaned items — \(Format.bytes(totalSize))")
    }

    private func scan() {
        scanning = true
        items = []
        progress = 0
        progressText = "Starting…"
        let reporter = ScanProgressReporter { fraction, text in
            progress = fraction
            progressText = text
        }
        Task.detached(priority: .userInitiated) {
            reporter.report(0, "Listing installed apps…", force: true)
            let apps = AppScanner.installedApps()
            let ids = AppScanner.installedBundleIDs(apps)
            let found = LeftoverScanner.orphans(installedBundleIDs: ids, progress: reporter, span: 0.05...1)
            await MainActor.run {
                items = found
                scanning = false
                hasScanned = true
            }
        }
    }
}
