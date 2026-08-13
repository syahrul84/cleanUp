import Foundation

/// Finds files an app leaves behind in ~/Library — both for a specific app being
/// uninstalled, and orphans belonging to apps that were deleted in the past.
enum LeftoverScanner {

    struct Location {
        let url: URL
        let label: String
        /// true when entries are single files matched by prefix (e.g. Preferences plists)
        let filePrefixMatch: Bool
    }

    static var locations: [Location] {
        let lib = FileUtils.home.appendingPathComponent("Library")
        return [
            .init(url: lib.appendingPathComponent("Application Support"), label: "Application Support", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("Caches"), label: "Caches", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("Preferences"), label: "Preferences", filePrefixMatch: true),
            .init(url: lib.appendingPathComponent("Containers"), label: "Containers", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("Group Containers"), label: "Group Containers", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("Saved Application State"), label: "Saved State", filePrefixMatch: true),
            .init(url: lib.appendingPathComponent("LaunchAgents"), label: "Launch Agents", filePrefixMatch: true),
            .init(url: lib.appendingPathComponent("Logs"), label: "Logs", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("HTTPStorages"), label: "HTTP Storage", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("WebKit"), label: "WebKit Data", filePrefixMatch: false),
        ]
    }

    /// Leftover candidates for one specific app (used by the uninstaller).
    static func leftovers(for app: AppInfo) -> [RemovalItem] {
        var needles: [String] = []
        if let bid = app.bundleID?.lowercased() { needles.append(bid) }
        let appName = app.name.lowercased()
        var items: [RemovalItem] = []

        for loc in locations where FileUtils.exists(loc.url) {
            for child in FileUtils.children(of: loc.url, includeHidden: true) {
                let entry = child.lastPathComponent.lowercased()
                let matchesBundleID = needles.contains { entry == $0 || entry.hasPrefix($0 + ".") }
                // Name match only for folder-per-app locations, and only exact — avoids
                // e.g. "Slack" matching "Slack Helper Whatever".
                let matchesName = !loc.filePrefixMatch && entry == appName
                guard matchesBundleID || matchesName else { continue }
                items.append(RemovalItem(id: child.path, url: child,
                                         label: loc.label, size: FileUtils.size(of: child)))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Reverse-DNS-looking entries in ~/Library that belong to no installed app → orphans.
    static func orphans(installedBundleIDs: Set<String>) -> [RemovalItem] {
        // Vendors whose files we never flag: Apple's own, and ambiguous shared data.
        let protectedPrefixes = ["com.apple.", "group.com.apple."]
        var items: [RemovalItem] = []

        for loc in locations where FileUtils.exists(loc.url) {
            for child in FileUtils.children(of: loc.url, includeHidden: true) {
                var entry = child.lastPathComponent.lowercased()
                for ext in [".plist", ".savedstate"] where entry.hasSuffix(ext) {
                    entry = String(entry.dropLast(ext.count))
                }
                // Only consider reverse-DNS names (at least vendor.tld.name) so we never
                // flag plain folders like "Firefox" whose ownership we can't prove.
                let parts = entry.split(separator: ".")
                guard parts.count >= 3 else { continue }
                guard !protectedPrefixes.contains(where: { entry.hasPrefix($0) }) else { continue }
                let owned = installedBundleIDs.contains { entry == $0 || entry.hasPrefix($0 + ".") }
                guard !owned else { continue }
                items.append(RemovalItem(id: child.path, url: child, label: loc.label,
                                         size: FileUtils.size(of: child), selected: false))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}
