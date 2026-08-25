import SwiftUI

struct HomebrewView: View {
    private enum Tab: String, CaseIterable {
        case updates = "Updates"
        case installed = "Installed"
    }

    @ObservedObject private var brew = HomebrewService.shared
    @State private var tab: Tab = .updates
    @State private var search = ""
    @State private var confirmUninstall: BrewPackage?
    @State private var showLog = false

    var body: some View {
        Group {
            if !brew.available {
                VStack(spacing: 12) {
                    Image(systemName: "mug").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("Homebrew is not installed on this Mac.")
                        .foregroundStyle(.secondary)
                    Link("Learn about Homebrew", destination: URL(string: "https://brew.sh")!)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(brew.scanning ? "Scanning…" : "Scan", systemImage: "arrow.clockwise") {
                    brew.scan()
                }
                .disabled(brew.scanning || brew.busyTitle != nil)
            }
        }
        .navigationTitle("Homebrew")
        .navigationSubtitle(brew.available && !brew.installed.isEmpty
            ? "\(brew.installed.count) packages" : "")
        .onAppear { brew.scan() }
        .confirmationDialog("Uninstall \(confirmUninstall?.name ?? "")?",
                            isPresented: .init(get: { confirmUninstall != nil },
                                               set: { if !$0 { confirmUninstall = nil } }),
                            titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) {
                if let package = confirmUninstall { brew.uninstall(package) }
                confirmUninstall = nil
            }
        } message: {
            Text("Removed via Homebrew (not the Trash). You can reinstall anytime with brew install.")
        }
    }

    // MARK: - Layout

    private var content: some View {
        VStack(spacing: 0) {
            if let title = brew.busyTitle {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(title).font(.callout)
                    Spacer()
                    Button(showLog ? "Hide Log" : "Show Log") { showLog.toggle() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }

            HStack(spacing: 12) {
                cleanupCard
                orphansCard
                updatesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            HStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(label(for: tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)

                Spacer()

                if tab == .installed {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter", text: $search)
                            .textFieldStyle(.plain)
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch tab {
                case .updates: updatesList
                case .installed: installedList
                }
            }
            .frame(maxHeight: .infinity)

            if showLog || (brew.busyTitle != nil && !brew.log.isEmpty) {
                logView
            }
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .updates: return brew.outdated.isEmpty ? "Updates" : "Updates (\(brew.outdated.count))"
        case .installed: return brew.installed.isEmpty ? "Installed" : "Installed (\(brew.installed.count))"
        }
    }

    // MARK: - Summary cards

    private var cleanupCard: some View {
        summaryCard(icon: "sparkles", tint: .blue,
                    title: "Reclaimable",
                    value: brew.cleanupEstimate ?? (brew.scanning ? "…" : "0 B"),
                    caption: "downloads & old versions") {
            Button("Clean Up") { brew.cleanUp() }
                .controlSize(.small)
                .disabled(brew.cleanupEstimate == nil || brew.busyTitle != nil)
        }
    }

    private var orphansCard: some View {
        summaryCard(icon: "puzzlepiece.extension", tint: .orange,
                    title: "Orphaned",
                    value: "\(brew.orphans.count)",
                    caption: brew.orphans.isEmpty ? "no unused dependencies"
                                                  : "unused dependencies") {
            Button("Remove") { brew.removeOrphans() }
                .controlSize(.small)
                .disabled(brew.orphans.isEmpty || brew.busyTitle != nil)
        }
    }

    private var updatesCard: some View {
        summaryCard(icon: "arrow.down.circle", tint: .green,
                    title: "Updates",
                    value: "\(brew.outdated.count)",
                    caption: brew.outdated.isEmpty ? "everything up to date"
                                                   : "packages outdated") {
            Button("Update All") { brew.upgradeAll() }
                .controlSize(.small)
                .disabled(brew.outdated.isEmpty || brew.busyTitle != nil)
        }
    }

    private func summaryCard(icon: String, tint: Color, title: String,
                             value: String, caption: String,
                             @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            action()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Lists

    private var updatesList: some View {
        Group {
            if brew.outdated.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: brew.scanning ? "hourglass" : "checkmark.seal")
                        .font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(brew.scanning ? "Checking for updates…" : "Everything is up to date.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(brew.outdated) { package in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(package.name)
                                if package.isCask { caskBadge }
                            }
                            HStack(spacing: 4) {
                                Text(package.installed).foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                                Text(package.latest).foregroundStyle(.green)
                            }
                            .font(.caption)
                        }
                        Spacer()
                        Button {
                            brew.upgrade(package)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .disabled(brew.busyTitle != nil)
                        .help("Update \(package.name)")
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var installedList: some View {
        List(filteredInstalled) { package in
            HStack {
                Image(systemName: package.isCask ? "app.dashed" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(package.name)
                if package.isCask { caskBadge }
                Spacer()
                Text(package.size.map { Format.bytes($0) } ?? "…")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button {
                    confirmUninstall = package
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(brew.busyTitle != nil)
                .help("Uninstall \(package.name)")
            }
            .padding(.vertical, 2)
        }
    }

    private var filteredInstalled: [BrewPackage] {
        search.isEmpty ? brew.installed
            : brew.installed.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var caskBadge: some View {
        Text("cask")
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    // MARK: - Log

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(brew.log)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id("logEnd")
            }
            .frame(height: 140)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .top) { Divider() }
            .onChange(of: brew.log) {
                proxy.scrollTo("logEnd", anchor: .bottom)
            }
        }
    }
}
