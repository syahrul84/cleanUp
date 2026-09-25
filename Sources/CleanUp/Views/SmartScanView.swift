import SwiftUI

/// One-click overview: junk categories + app leftovers + Trash, with a total
/// reclaimable figure and a single clean action.
struct SmartScanView: View {

    struct Row: Identifiable {
        let id: String
        let name: String
        let icon: String
        let detail: String
        var items: [RemovalItem]
        var included: Bool
        var size: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    @State private var rows: [Row] = []
    @State private var scanning = false
    @State private var hasScanned = false
    @State private var progressText = "Scanning…"
    @State private var progress = 0.0

    private var includedItems: [RemovalItem] { rows.filter(\.included).flatMap(\.items) }
    private var includedSize: Int64 { includedItems.reduce(0) { $0 + $1.size } }
    private var totalSize: Int64 { rows.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48)).foregroundStyle(.tint)
                    Text("Smart Scan").font(.largeTitle.bold())
                    Text("Checks junk, app leftovers and Trash in one pass.\nNothing is removed without your confirmation.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if scanning {
                        VStack(spacing: 6) {
                            UsageBar(fraction: progress, height: 6)
                            HStack {
                                Text(progressText).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(Int(progress * 100))%").monospacedDigit()
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 380)
                    } else {
                        Button { scan() } label: {
                            Text(hasScanned ? "Scan Again" : "Start Smart Scan")
                                .font(.title3).padding(.horizontal, 12).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        if hasScanned {
                            Text("Nothing left to clean — your Mac is tidy!")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Text(Format.bytes(includedSize)).font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.tint)
                    Text("selected of \(Format.bytes(totalSize)) reclaimable")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 14)

                ScrollView {
                    SectionCard(title: "What was found", icon: "list.bullet.rectangle", tint: .accentColor,
                                info: "Switch on the categories you want cleaned. Risky ones — iOS backups, the Trash and app leftovers — start switched off. Everything goes to the Trash, so it can be restored.") {
                        ForEach($rows) { $row in
                            HoverRow(highlight: .accentColor) {
                                IconTile(systemName: row.icon, tint: .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text(Format.bytes(row.size)).font(.callout).monospacedDigit()
                                    .foregroundStyle(row.included ? .primary : .secondary)
                                Toggle("", isOn: $row.included).labelsHidden().toggleStyle(.switch)
                            }
                        }
                    }
                    .padding(16)
                }

                ResultsActionBar(rescanTitle: "Scan Again", scanning: scanning, rescan: scan) {
                    TrashActionButton(count: includedItems.count, size: includedSize,
                                      urls: { includedItems.map(\.url) }) { scan() }
                }
            }
        }
        .navigationTitle("Smart Scan")
        .onReceive(NotificationCenter.default.publisher(for: .runSmartScan)) { _ in
            if !scanning { scan() }
        }
    }

    private func scan() {
        scanning = true
        rows = []
        progressText = "Scanning junk…"
        progress = 0
        let reporter = ScanProgressReporter { fraction, text in
            progress = fraction
            progressText = text
        }
        Task.detached(priority: .userInitiated) {
            let junk = JunkScanner.scan(progress: reporter, span: 0...0.7)
            reporter.report(0.7, "Finding app leftovers…", force: true)
            let apps = AppScanner.installedApps()
            let orphans = LeftoverScanner.orphans(installedBundleIDs: AppScanner.installedBundleIDs(apps),
                                                  progress: reporter, span: 0.72...1)

            var result: [Row] = junk.map { category in
                Row(id: category.kind.rawValue,
                    name: category.kind.rawValue,
                    icon: category.kind.systemImage,
                    detail: category.kind.explanation,
                    items: category.items,
                    included: category.kind.defaultSelected)
            }
            if !orphans.isEmpty {
                result.append(Row(id: "leftovers",
                                  name: "App Leftovers",
                                  icon: "magnifyingglass",
                                  detail: "Files from apps that appear to be deleted. Review in Leftover Finder before including.",
                                  items: orphans,
                                  included: false))
            }
            let final = result.filter { !$0.items.isEmpty }.sorted { $0.size > $1.size }
            await MainActor.run {
                rows = final
                scanning = false
                hasScanned = true
            }
        }
    }
}
