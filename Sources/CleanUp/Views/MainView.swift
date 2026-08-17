import SwiftUI

enum Feature: String, CaseIterable, Identifiable {
    case smartScan = "Smart Scan"
    case speed = "Speed"
    case memoryWatch = "Memory Watch"
    case uninstaller = "App Uninstaller"
    case junk = "Junk Cleaner"
    case duplicates = "Duplicate Finder"
    case largeFiles = "Large & Old Files"
    case leftovers = "Leftover Finder"
    case startupItems = "Startup Items"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .smartScan: return "wand.and.stars"
        case .speed: return "speedometer"
        case .memoryWatch: return "memorychip"
        case .uninstaller: return "xmark.bin"
        case .junk: return "sparkles"
        case .duplicates: return "doc.on.doc"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        case .leftovers: return "magnifyingglass"
        case .startupItems: return "power"
        }
    }
}

struct MainView: View {
    @State private var selection: Feature? = .smartScan
    @StateObject private var updater = Updater.shared

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.rawValue, systemImage: feature.systemImage).tag(feature)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .top) {
                SidebarHeader()
            }
            .safeAreaInset(edge: .bottom) {
                FullDiskAccessHint()
            }
        } detail: {
            switch selection ?? .smartScan {
            case .smartScan: SmartScanView()
            case .speed: SpeedView()
            case .memoryWatch: MemoryWatchView()
            case .uninstaller: UninstallerView()
            case .junk: JunkView()
            case .duplicates: DuplicatesView()
            case .largeFiles: LargeFilesView()
            case .leftovers: LeftoversView()
            case .startupItems: StartupItemsView()
            }
        }
        .navigationTitle("CleanUp")
        .onReceive(AppState.shared.$smartScanRequest.dropFirst()) { _ in
            selection = .smartScan
        }
        .onReceive(AppState.shared.$openFeatureRequest.compactMap { $0 }) { feature in
            selection = feature
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let release = updater.available {
                UpdateBanner(release: release, updater: updater)
            }
        }
        .alert("Software Update", isPresented: .init(
            get: { updater.phase == .upToDate || isFailed },
            set: { if !$0 { updater.phase = .idle } })) {
            Button("OK") { updater.phase = .idle }
        } message: {
            if case .failed(let message) = updater.phase {
                Text("Update check failed: \(message)")
            } else {
                Text("CleanUp \(updater.currentVersion) is the latest version.")
            }
        }
        .task { updater.check() }
    }

    private var isFailed: Bool {
        if case .failed = updater.phase { return true }
        return false
    }
}

/// Slim banner across the top of the window when a new version is available.
struct UpdateBanner: View {
    let release: Updater.Release
    @ObservedObject var updater: Updater

    private var busy: Bool {
        updater.phase == .downloading || updater.phase == .installing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
            Text("CleanUp \(release.version) is available")
                .fontWeight(.medium)
            Spacer()
            Button {
                updater.installUpdate()
            } label: {
                if busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(updater.phase == .installing ? "Installing…" : "Downloading…")
                    }
                } else {
                    Text("Update Now")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            Button {
                updater.available = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(busy)
            .help("Remind me next launch")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Full-width logo banner at the top of the sidebar, with the app name
/// centered on it and the version in the bottom-right corner.
struct SidebarHeader: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "v\(v)"
    }

    private var logo: NSImage {
        Bundle.main.url(forResource: "SidebarLogo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSApp.applicationIconImage
    }

    var body: some View {
        Color.clear
            .frame(height: 110)
            .overlay {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
            .clipped()
            .overlay {
                Text("CleanUp")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(version)
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .padding(6)
            }
            // .clipped() clips drawing but NOT hit-testing — without this, the
            // scaled-to-fill image's invisible overflow steals clicks from the
            // first sidebar rows below the banner.
            .allowsHitTesting(false)
    }
}

/// Custom About window: logo, version, and support/repo links.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
            Text("CleanUp").font(.title.bold())
            Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
            Text("A free, open-source Mac cleaner.\nNo subscriptions, no snake oil.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://ko-fi.com/syahrul84")!) {
                Label("Send me a tip", systemImage: "cup.and.saucer.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)

            Link(destination: URL(string: "https://github.com/syahrul84/cleanUp")!) {
                Label("Star on GitHub", systemImage: "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("© 2026 Syahrul Farhan · MIT License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 280)
    }
}

/// Full Disk Access is required to see everything. Probe by actually opening the
/// user TCC database — it exists on every macOS install and is always FDA-protected.
/// (A stat/access() check is not enough: TCC only blocks at open time, and a probe
/// file that happens not to exist would read as "no access" forever.)
struct FullDiskAccessHint: View {
    @State private var hasFullDiskAccess = Self.check()

    private static func check() -> Bool {
        let probe = FileUtils.home
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = FileHandle(forReadingAtPath: probe.path) else { return false }
        try? handle.close()
        return true
    }

    var body: some View {
        if !hasFullDiskAccess {
            VStack(alignment: .leading, spacing: 6) {
                Label("Limited access", systemImage: "lock.shield")
                    .font(.caption.bold())
                Text("Grant Full Disk Access in System Settings for complete scans.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Open Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                    NSWorkspace.shared.open(url)
                }
                .font(.caption2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .padding(8)
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)) { _ in
                hasFullDiskAccess = Self.check()
            }
        }
    }
}
