import SwiftUI

struct UninstallerView: View {
    @State private var apps: [AppInfo] = []
    @State private var scanning = false
    @State private var search = ""
    @State private var uninstallTarget: AppInfo?

    private var filtered: [AppInfo] {
        search.isEmpty ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if apps.isEmpty {
                ScanPlaceholder(scanning: scanning, emptyIcon: "xmark.bin",
                                emptyText: "Scan to list installed applications.")
            } else {
                List(filtered) { app in
                    HStack {
                        Image(nsImage: app.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.bundleID ?? app.url.path)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(app.size)).monospacedDigit().foregroundStyle(.secondary)
                        Button("Uninstall…") { uninstallTarget = app }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }
                .searchable(text: $search, prompt: "Filter apps")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(scanning ? "Scanning…" : "Scan", systemImage: "arrow.clockwise") { scan() }
                    .disabled(scanning)
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
        scanning = true
        Task.detached(priority: .userInitiated) {
            let found = AppScanner.installedApps()
            await MainActor.run { apps = found; scanning = false }
            // Fill in sizes progressively; the list is already usable.
            for app in found {
                let size = FileUtils.size(of: app.url)
                await MainActor.run {
                    if let idx = apps.firstIndex(of: app) { apps[idx].size = size }
                }
            }
        }
    }
}

struct UninstallSheet: View {
    let app: AppInfo
    var onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var appItem: RemovalItem?
    @State private var leftovers: [RemovalItem] = []
    @State private var loading = true

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
                ProgressView("Finding related files…")
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
                                  size: allSelected.reduce(0) { $0 + $1.size }) {
                    FileUtils.trash(allSelected.map(\.url))
                } onDone: {
                    dismiss()
                    onFinished()
                }
            }
        }
        .padding()
        .frame(width: 560, height: 460)
        .task {
            let target = app
            let found = await Task.detached(priority: .userInitiated) {
                LeftoverScanner.leftovers(for: target)
            }.value
            appItem = RemovalItem(id: target.url.path, url: target.url, label: "Application",
                                  size: target.size ?? FileUtils.size(of: target.url))
            leftovers = found
            loading = false
        }
    }
}
