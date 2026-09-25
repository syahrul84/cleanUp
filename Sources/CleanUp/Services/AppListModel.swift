import Foundation
import CoreServices
import AppKit

/// Installed-app list for the uninstaller, with sizes and last-used dates
/// filled in progressively. Lives outside the view so background updates
/// always land, even if SwiftUI recreates the view.
final class AppListModel: ObservableObject {
    static let shared = AppListModel()

    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var scanning = false

    private let queue = DispatchQueue(label: "app-list", qos: .userInitiated)
    private var generation = 0 // ignores results from superseded scans

    func scan() {
        guard !scanning else { return }
        scanning = true
        generation += 1
        let gen = generation
        queue.async { [self] in
            let found = AppScanner.installedApps()
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.apps = found
                self.scanning = false
            }

            // Last-used dates: cheap lookups, done before sizes.
            let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
            var dates: [String: Date] = [:]
            for app in found {
                dates[app.id] = running.contains(app.url.path) ? Date() : Self.lastActivity(of: app)
            }
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                for i in self.apps.indices { self.apps[i].lastUsed = dates[self.apps[i].id] }
            }

            // Sizes, one app at a time (large apps like Xcode take a while).
            for app in found {
                let size = FileUtils.size(of: app.url)
                DispatchQueue.main.async {
                    guard gen == self.generation,
                          let idx = self.apps.firstIndex(where: { $0.id == app.id }) else { return }
                    self.apps[idx].size = size
                }
            }
        }
    }

    /// Most recent sign of use. Spotlight's kMDItemLastUsedDate alone is
    /// unreliable: apps that self-update by replacing their bundle (VS Code,
    /// Chrome, Office) often lose it entirely. So also look at the files an
    /// app writes while it runs — preferences, data folders, saved state.
    static func lastActivity(of app: AppInfo) -> Date? {
        var candidates: [Date] = []
        if let item = MDItemCreateWithURL(nil, app.url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            candidates.append(date)
        }
        let lib = FileUtils.home.appendingPathComponent("Library")
        var paths: [URL] = []
        if let bid = app.bundleID {
            paths += [
                lib.appendingPathComponent("Preferences/\(bid).plist"),
                lib.appendingPathComponent("Application Support/\(bid)"),
                lib.appendingPathComponent("Containers/\(bid)"),
                lib.appendingPathComponent("Saved Application State/\(bid).savedState"),
            ]
        }
        // Many apps name their data folder after the app or its executable
        // (VS Code uses "Code").
        var names = [app.name, app.url.deletingPathExtension().lastPathComponent]
        if let exe = Bundle(url: app.url)?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
            names.append(exe)
        }
        for name in Set(names) {
            paths.append(lib.appendingPathComponent("Application Support/\(name)"))
        }
        for path in paths {
            if let date = (try? path.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate {
                candidates.append(date)
            }
        }
        // Never report activity in the future (clock skew, odd timestamps).
        return candidates.filter { $0 <= Date() }.max()
    }
}
