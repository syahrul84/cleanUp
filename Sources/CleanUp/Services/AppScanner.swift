import Foundation
import AppKit

enum AppScanner {
    static var searchDirs: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileUtils.home.appendingPathComponent("Applications")]
    }

    /// All .app bundles in /Applications and ~/Applications (one level of subfolders too).
    static func installedApps() -> [AppInfo] {
        var apps: [AppInfo] = []
        for dir in searchDirs where FileUtils.exists(dir) {
            for child in FileUtils.children(of: dir) {
                if child.pathExtension == "app" {
                    apps.append(makeInfo(child))
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // e.g. /Applications/Utilities
                    for nested in FileUtils.children(of: child) where nested.pathExtension == "app" {
                        apps.append(makeInfo(nested))
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func makeInfo(_ url: URL) -> AppInfo {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return AppInfo(id: url.path, name: name, bundleID: bundle?.bundleIdentifier,
                       url: url, size: nil, icon: icon)
    }

    /// All bundle IDs of installed apps, lowercased — used by the leftover/orphan scanner.
    static func installedBundleIDs(_ apps: [AppInfo]) -> Set<String> {
        Set(apps.compactMap { $0.bundleID?.lowercased() })
    }
}
