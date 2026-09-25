import SwiftUI

struct JunkView: View {
    @State private var categories: [JunkCategory] = []
    @State private var scanning = false
    @State private var hasScanned = false
    @State private var progress = 0.0
    @State private var progressText = "Starting…"
    @State private var expanded: Set<String> = []

    private var selectedItems: [RemovalItem] {
        categories.flatMap(\.items).filter(\.selected)
    }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        Group {
            if categories.isEmpty {
                ScanHero(icon: "sparkles",
                         title: "Junk Cleaner",
                         description: "Finds caches, logs, Xcode leftovers, developer and browser caches, old iOS backups and Trash.\nNothing is removed without your confirmation.",
                         buttonTitle: hasScanned ? "Scan Again" : "Start Scan",
                         scanning: scanning,
                         progressText: progressText,
                         progress: progress,
                         resultNote: hasScanned ? "No junk found — nice and clean!" : nil) { scan() }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            SummaryCard(icon: "sparkles", tint: .blue,
                                        title: "\(Format.bytes(totalSize)) of junk found",
                                        subtitle: "\(selectedItems.count) items selected · \(Format.bytes(selectedSize)) will move to the Trash")
                            ForEach($categories) { $category in
                                categoryCard($category)
                            }
                        }
                        .padding(16)
                    }
                    ResultsActionBar(rescanTitle: "Scan Again", scanning: scanning, rescan: scan) {
                        TrashActionButton(count: selectedItems.count, size: selectedSize,
                                          urls: { selectedItems.map(\.url) }) { scan() }
                    }
                }
            }
        }
        .navigationTitle("Junk Cleaner")
        .navigationSubtitle(categories.isEmpty ? "" : "Reclaimable: \(Format.bytes(totalSize))")
    }

    @ViewBuilder
    private func categoryCard(_ category: Binding<JunkCategory>) -> some View {
        let kind = category.wrappedValue.kind
        let isOpen = expanded.contains(kind.id)
        let selected = category.wrappedValue.items.filter(\.selected)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                SelectAllBox(items: category.items)
                IconTile(systemName: kind.systemImage, tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.rawValue).font(.headline)
                    Text(kind.explanation)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.bytes(category.wrappedValue.totalSize))
                        .font(.callout.bold()).monospacedDigit()
                    Text("\(selected.count) of \(category.wrappedValue.items.count) selected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(kind.id) } else { expanded.insert(kind.id) }
                }
            }
            if isOpen {
                Divider().padding(.vertical, 2)
                ForEach(category.items) { $item in
                    FileRow(item: $item)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func scan() {
        scanning = true
        categories = []
        progress = 0
        progressText = "Starting…"
        let reporter = ScanProgressReporter { fraction, text in
            progress = fraction
            progressText = text
        }
        Task.detached(priority: .userInitiated) {
            let result = JunkScanner.scan(progress: reporter)
            await MainActor.run {
                categories = result
                scanning = false
                hasScanned = true
            }
        }
    }
}
