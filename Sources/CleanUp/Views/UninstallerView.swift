import SwiftUI

struct UninstallerView: View {
    @ObservedObject private var model = AppListModel.shared
    @State private var search = ""

    private var apps: [AppInfo] { model.apps }
    private var scanning: Bool { model.scanning }
    @State private var uninstallTarget: AppInfo?
    @State private var sortOrder: SortOrder = .name

    private enum SortOrder: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case lastUsed = "Last Used"

        var icon: String {
            switch self {
            case .name: return "textformat"
            case .size: return "internaldrive"
            case .lastUsed: return "clock"
            }
        }
    }

    private var filtered: [AppInfo] {
        let matching = search.isEmpty ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        switch sortOrder {
        case .name:
            return matching
        case .size:
            return matching.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        case .lastUsed:
            // Least recently used first — the best uninstall candidates.
            return matching.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    private func lastUsedText(_ date: Date?) -> String {
        guard let date else { return "Never opened" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "Used today" }
        return "Last used " + date.formatted(.relative(presentation: .named))
    }

    private func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) > 90 * 86_400
    }

    var body: some View {
        Group {
            if apps.isEmpty {
                ScanHero(icon: "xmark.bin",
                         title: "App Uninstaller",
                         description: "Removes apps together with the support files, caches and preferences they leave behind.\nYou review everything before it moves to the Trash.",
                         buttonTitle: "Find Apps",
                         scanning: scanning,
                         progressText: "Finding installed apps…") { scan() }
            } else {
                VStack(spacing: 0) {
                StatBanner(icon: "xmark.bin", tint: .blue,
                           title: "\(apps.count) applications",
                           caption: apps.contains { $0.size != nil }
                               ? "Using \(Format.bytes(apps.compactMap(\.size).reduce(0, +))) of disk"
                               : "Calculating sizes…")
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter apps", text: $search)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 260)
                    Spacer()
                    Text("Sort by").font(.caption).foregroundStyle(.secondary)
                    IconTabBar(items: SortOrder.allCases.map { ($0, $0.rawValue, $0.icon) },
                               selection: $sortOrder, small: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                List(filtered) { app in
                    AppRow(app: app,
                           lastUsedText: lastUsedText(app.lastUsed),
                           stale: isStale(app.lastUsed)) {
                        uninstallTarget = app
                    }
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .listRowSeparator(.hidden)
                }
                ResultsActionBar(rescanTitle: "Refresh List", scanning: scanning, rescan: scan) {
                    EmptyView()
                }
                }
            }
        }
        .sheet(item: $uninstallTarget) { app in
            UninstallSheet(app: app) { scan() }
        }
        .navigationTitle("App Uninstaller")
        .navigationSubtitle(apps.isEmpty ? "" : "\(apps.count) applications")
        .onAppear { if apps.isEmpty && !scanning { scan() } }
    }

    private func scan() {
        model.scan()
    }
}

struct UninstallSheet: View {
    let app: AppInfo
    var onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var appItem: RemovalItem?
    @State private var leftovers: [RemovalItem] = []
    @State private var loading = true
    @State private var progressText = "Finding related files…"

    private var allSelected: [RemovalItem] {
        ([appItem].compactMap { $0 } + leftovers).filter(\.selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: app.icon)
                Text("Uninstall \(app.name)").font(.title2.bold())
            }
            if loading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(progressText).foregroundStyle(.secondary)
                    Text("Large apps with lots of data (chats, media) can take a minute.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if appItem != nil {
                        Section("Application") {
                            RemovalRow(item: Binding($appItem)!, showPath: true)
                        }
                    }
                    Section("Related files (\(leftovers.count))") {
                        if leftovers.isEmpty {
                            Text("No leftover files found.").foregroundStyle(.secondary)
                        }
                        ForEach($leftovers) { $item in
                            RemovalRow(item: $item, showPath: true)
                        }
                    }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                TrashActionButton(count: allSelected.count,
                                  size: allSelected.reduce(0) { $0 + $1.size },
                                  urls: { allSelected.map(\.url) }) {
                    dismiss()
                    onFinished()
                }
            }
        }
        .padding()
        .frame(width: 560, height: 460)
        .task {
            let target = app
            // Everything heavy happens off the main thread — including the
            // app-bundle size, which may not be computed yet.
            let (found, appSize) = await Task.detached(priority: .userInitiated) {
                let found = LeftoverScanner.leftovers(for: target) { text in
                    Task { @MainActor in progressText = text }
                }
                let size = target.size ?? FileUtils.size(of: target.url)
                return (found, size)
            }.value
            appItem = RemovalItem(id: target.url.path, url: target.url, label: "Application",
                                  size: appSize)
            leftovers = found
            loading = false
        }
    }
}

/// One app row with a hover highlight, so the name on the left and the
/// size/uninstall controls on the right read as one line.
private struct AppRow: View {
    let app: AppInfo
    let lastUsedText: String
    let stale: Bool
    let onUninstall: () -> Void

    @State private var hovered = false
    @State private var trashHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.bundleID ?? app.url.path)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(app.size))
                    .font(.callout).monospacedDigit()
                Label(lastUsedText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(trashHovered ? .white : .red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(trashHovered ? 0.85 : 0.12),
                                in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .onHover { trashHovered = $0 }
            .help("Uninstall \(app.name)…")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovered ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
