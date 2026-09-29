import SwiftUI

struct HomebrewView: View {
    private enum Tab: String, CaseIterable {
        case updates = "Updates"
        case installed = "Installed"
        case adoptable = "Adoptable"
        case discover = "Discover"

        var icon: String {
            switch self {
            case .updates: return "arrow.down.circle"
            case .installed: return "checkmark.circle"
            case .adoptable: return "square.and.arrow.down"
            case .discover: return "sparkle.magnifyingglass"
            }
        }
    }

    private enum PackageKind: String, CaseIterable {
        case apps = "Apps"
        case services = "Services & CLI Tools"

        var icon: String {
            switch self {
            case .apps: return "app.badge"
            case .services: return "terminal"
            }
        }
    }

    @ObservedObject private var brew = HomebrewService.shared
    @State private var tab: Tab = .updates
    @State private var packageKind: PackageKind = .apps
    @State private var search = ""
    @State private var discoverQuery = ""
    @State private var confirmUninstall: BrewPackage?
    @State private var showLog = false
    @State private var showAdoptInfo = false

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
        .alert("Quit apps to update?", isPresented: .init(
            get: { brew.quitRequest != nil },
            set: { if !$0 { brew.quitRequest = nil } })) {
            Button("Quit & Update") { brew.confirmQuitAndUpdate() }
            Button("Cancel", role: .cancel) { brew.quitRequest = nil }
        } message: {
            Text("\(brew.quitRequest?.names ?? "") is open. CleanUp will download the update first, then quit the app, install it and reopen it. If it won't quit (for example unsaved work), the update waits and installs automatically when you close it.")
        }
        .alert("Admin password needed", isPresented: .init(
            get: { brew.terminalFallback != nil },
            set: { if !$0 { brew.terminalFallback = nil } })) {
            Button("Continue in Terminal") { brew.continueInTerminal() }
            Button("Cancel", role: .cancel) { brew.terminalFallback = nil }
        } message: {
            Text("This app needs an ownership fix that requires your admin password — Homebrew can only ask for it in Terminal. CleanUp will open Terminal with the exact command; enter your password there, then press Scan here when it finishes.")
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
                adoptableCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            HStack {
                IconTabBar(items: Tab.allCases.map { ($0, label(for: $0), $0.icon) },
                           selection: $tab)

                Spacer()

                if tab == .updates && !brew.outdated.isEmpty {
                    Button("Update All") { brew.upgradeAll() }
                        .controlSize(.small)
                        .disabled(brew.busyTitle != nil)
                }

                if tab == .adoptable && !brew.adoptable.isEmpty {
                    Button("Adopt All") { brew.adoptAll() }
                        .controlSize(.small)
                        .disabled(brew.busyTitle != nil)
                }

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

                if tab == .discover {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search apps", text: $discoverQuery)
                            .textFieldStyle(.plain)
                            .frame(width: 180)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if tab == .updates || tab == .installed {
                HStack {
                    IconTabBar(items: PackageKind.allCases.map { ($0, subLabel(for: $0), $0.icon) },
                               selection: $packageKind, small: true)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Group {
                switch tab {
                case .updates: updatesList
                case .installed: installedList
                case .adoptable: adoptableList
                case .discover: discoverList
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
        case .adoptable: return brew.adoptable.isEmpty ? "Adoptable" : "Adoptable (\(brew.adoptable.count))"
        case .discover: return "Discover"
        }
    }

    private func subLabel(for kind: PackageKind) -> String {
        let count: Int
        switch tab {
        case .updates:
            count = brew.outdated.filter { $0.isCask == (kind == .apps) }.count
        default:
            count = brew.installed.filter { $0.isCask == (kind == .apps) }.count
        }
        return count == 0 ? kind.rawValue : "\(kind.rawValue) (\(count))"
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

    private var adoptableCard: some View {
        summaryCard(icon: "square.and.arrow.down", tint: .cyan,
                    title: "Adoptable",
                    value: "\(brew.adoptable.count)",
                    caption: brew.adoptable.isEmpty ? "no apps to hand to brew"
                                                    : "apps Homebrew can manage") {
            Button("View") { tab = .adoptable }
                .controlSize(.small)
                .disabled(brew.adoptable.isEmpty)
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

    private var pendingCard: some View {
        SectionCard(title: "Waiting to install (\(brew.pending.count))", icon: "clock.arrow.circlepath", tint: .orange,
                    info: "These updates are downloaded but their apps were open. Each one installs automatically as soon as you quit the app — or when CleanUp starts after a restart.") {
            ForEach(brew.pending) { item in
                HoverRow {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.appPath))
                        .resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.appName)
                        Text("Installs when \(item.appName) closes").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { brew.cancelPending(item) }.controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var updatesList: some View {
        let rows = brew.outdated.filter { $0.isCask == (packageKind == .apps) }
        return VStack(spacing: 0) {
            if !brew.pending.isEmpty { pendingCard }
            updatesListBody(rows)
        }
    }

    private func updatesListBody(_ rows: [BrewOutdated]) -> some View {
        Group {
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: brew.scanning ? "hourglass" : "checkmark.seal")
                        .font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(brew.scanning ? "Checking for updates…"
                         : brew.outdated.isEmpty ? "Everything is up to date."
                         : packageKind == .apps ? "All apps are up to date."
                                                : "All services & CLI tools are up to date.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { package in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(package.name)
                                if package.selfUpdating {
                                    Label("Updates itself", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                        .help("This app also updates itself. Opening it may install this update too — or update here to get it now through Homebrew.")
                                }
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
        let rows = filteredInstalled.filter { $0.isCask == (packageKind == .apps) }
        return Group {
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(search.isEmpty ? "Nothing installed in this category."
                                        : "No matches for “\(search)” here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { installedRow($0) }
            }
        }
    }

    @ViewBuilder
    private func installedRow(_ package: BrewPackage) -> some View {
        HStack {
            if let icon = package.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: package.isCask ? "app.dashed" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            Text(package.name)
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

    private var adoptableList: some View {
        Group {
            if brew.adoptable.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: brew.scanning ? "hourglass" : "checkmark.seal")
                        .font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(brew.catalogUnavailable
                         ? "Homebrew's app catalog couldn't be downloaded — check your internet connection, then press Scan to retry."
                         : brew.scanning ? "Matching your apps against the cask catalog…"
                                         : "Nothing to adopt — your apps are App Store, brew-managed, or not in the catalog.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
            } else {
                List {
                    Section {
                        ForEach(brew.adoptable) { app in
                            HStack {
                                Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                    Text("brew cask: \(app.caskToken)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if app.autoUpdates {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .help("This app also updates itself — adopting still works; Homebrew tracks it as self-updating")
                                }
                                Spacer()
                                Button("Adopt") { brew.adopt(app) }
                                    .controlSize(.small)
                                    .disabled(brew.busyTitle != nil)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack(spacing: 5) {
                            Text("Apps Homebrew can take over")
                            Button {
                                showAdoptInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .popover(isPresented: $showAdoptInfo, arrowEdge: .bottom) {
                                Text("Adopting doesn't reinstall or touch the app — Homebrew just takes over future updates (brew install --cask --adopt). Your settings and data are untouched.\n\nIf adoption fails because your installed version differs from Homebrew's, update the app first and try again.")
                                    .font(.callout)
                                    .frame(width: 340, alignment: .leading)
                                    .padding()
                            }
                        }
                    }
                }
            }
        }
    }

    private var discoverResults: [DiscoverCask] {
        let query = discoverQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let matches = brew.catalog.filter {
            $0.token.lowercased().contains(query)
                || $0.displayName.lowercased().contains(query)
                || $0.desc.lowercased().contains(query)
        }
        // Name/token hits before description-only hits, then alphabetical.
        return Array(matches.sorted {
            let aDirect = $0.displayName.lowercased().contains(query) || $0.token.lowercased().contains(query)
            let bDirect = $1.displayName.lowercased().contains(query) || $1.token.lowercased().contains(query)
            if aDirect != bDirect { return aDirect }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }.prefix(50))
    }

    private var discoverList: some View {
        let searching = !discoverQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let rows = searching ? discoverResults : brew.popular
        return Group {
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: brew.catalogUnavailable ? "wifi.slash"
                          : searching ? "questionmark.circle" : "hourglass")
                        .font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(emptyDiscoverMessage(searching: searching))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
            } else {
                List {
                    Section {
                        ForEach(rows) { cask in
                            discoverRow(cask)
                        }
                    } header: {
                        Text(searching ? "Results" : "Popular this month (via Homebrew's install stats)")
                    } footer: {
                        Text("Apps installed here stay updatable and cleanly removable through Homebrew. A few apps use Apple installer packages that need an admin password Homebrew can't ask for inside CleanUp — if an install fails, the log says why, and running the shown brew command in Terminal is the fallback.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func emptyDiscoverMessage(searching: Bool) -> String {
        if brew.catalogUnavailable {
            return "Homebrew's app catalog couldn't be downloaded — check your internet connection, then press Scan to retry. Everything else in CleanUp works offline."
        }
        if searching {
            return "No apps in the Homebrew catalog match “\(discoverQuery)”."
        }
        return brew.scanning ? "Loading popular apps…"
            : "The popular-apps list isn't available right now — search still works."
    }

    @ViewBuilder
    private func discoverRow(_ cask: DiscoverCask) -> some View {
        HStack {
            CaskIconView(cask: cask)
            VStack(alignment: .leading, spacing: 2) {
                Text(cask.displayName)
                Text(cask.desc.isEmpty ? "brew install --cask \(cask.token)" : cask.desc)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if brew.installedCaskTokens.contains(cask.token) {
                Text("Installed")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            } else {
                Button("Install") { brew.install(cask) }
                    .controlSize(.small)
                    .disabled(brew.busyTitle != nil)
            }
        }
        .padding(.vertical, 2)
        .help("brew install --cask \(cask.token)")
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

/// Icon for a not-yet-installed cask: vendor site icon with a colored
/// monogram fallback (hue hashed from the token, stable across launches).
struct CaskIconView: View {
    let cask: DiscoverCask
    @State private var icon: NSImage?
    @State private var requested = false

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Text(String(cask.displayName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(monogramColor, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .onAppear {
            guard !requested else { return }
            requested = true
            CaskIconStore.shared.icon(for: cask.token, homepage: cask.homepage) { icon = $0 }
        }
    }

    private var monogramColor: Color {
        let hue = Double(abs(cask.token.hashValue % 256)) / 256.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}
