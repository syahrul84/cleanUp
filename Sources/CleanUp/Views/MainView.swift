import SwiftUI

enum Feature: String, CaseIterable, Identifiable {
    case uninstaller = "App Uninstaller"
    case junk = "Junk Cleaner"
    case duplicates = "Duplicate Finder"
    case largeFiles = "Large & Old Files"
    case leftovers = "Leftover Finder"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .uninstaller: return "xmark.bin"
        case .junk: return "sparkles"
        case .duplicates: return "doc.on.doc"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        case .leftovers: return "magnifyingglass"
        }
    }
}

struct MainView: View {
    @State private var selection: Feature? = .junk

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.rawValue, systemImage: feature.systemImage).tag(feature)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                FullDiskAccessHint()
            }
        } detail: {
            switch selection ?? .junk {
            case .uninstaller: UninstallerView()
            case .junk: JunkView()
            case .duplicates: DuplicatesView()
            case .largeFiles: LargeFilesView()
            case .leftovers: LeftoversView()
            }
        }
        .navigationTitle("CleanUp")
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
