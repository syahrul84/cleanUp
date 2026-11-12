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

    /// Extra places only the uninstaller looks: system-wide folders (helpers,
    /// daemons — removing them asks for an admin password) and the top of
    /// ~/Library, where some apps keep a data folder named after themselves.
    private static var uninstallLocations: [Location] {
        let lib = FileUtils.home.appendingPathComponent("Library")
        let sys = URL(fileURLWithPath: "/Library")
        return locations + [
            .init(url: lib, label: "Library", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("Application Scripts"), label: "Application Scripts", filePrefixMatch: false),
            .init(url: lib.appendingPathComponent("Cookies"), label: "Cookies", filePrefixMatch: true),
            .init(url: lib.appendingPathComponent("Preferences/ByHost"), label: "Preferences", filePrefixMatch: true),
            .init(url: sys.appendingPathComponent("Application Support"), label: "System Application Support", filePrefixMatch: false),
            .init(url: sys.appendingPathComponent("Caches"), label: "System Caches", filePrefixMatch: false),
            .init(url: sys.appendingPathComponent("Preferences"), label: "System Preferences", filePrefixMatch: true),
            .init(url: sys.appendingPathComponent("Logs"), label: "System Logs", filePrefixMatch: false),
            .init(url: sys.appendingPathComponent("LaunchAgents"), label: "System Launch Agents", filePrefixMatch: true),
            .init(url: sys.appendingPathComponent("LaunchDaemons"), label: "Launch Daemons", filePrefixMatch: true),
            .init(url: sys.appendingPathComponent("PrivilegedHelperTools"), label: "Helper Tools", filePrefixMatch: true),
        ]
    }

    /// macOS's own folders at the top of ~/Library — never an app's data,
    /// even when an app shares the name.
    private static let standardLibraryFolders: Set<String> = [
        "accounts", "application scripts", "application support", "assistant", "audio", "autosave information",
        "caches", "calendars", "colorpickers", "colors", "compositions", "containers", "cookies", "developer",
        "favorites", "fonts", "group containers", "httpstorages", "input methods", "internet plug-ins",
        "keyboard layouts", "keychains", "launchagents", "logs", "mail", "messages", "metadata",
        "mobile documents", "passes", "preferencepanes", "preferences", "printers", "safari",
        "saved application state", "screen savers", "services", "sounds", "spelling", "webkit",
    ]

    /// Leftover candidates for one specific app (used by the uninstaller).
    /// `progress` is called with a human-readable status as locations are
    /// scanned and large folders are measured.
    static func leftovers(for app: AppInfo,
                          progress: ((String) -> Void)? = nil) -> [RemovalItem] {
        // Developers (first two ID parts) of every other installed app:
        // anything named after one of them may be shared, so it's left alone.
        func vendor(_ id: String) -> String? {
            let parts = id.split(separator: ".")
            return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : nil
        }
        let others = AppScanner.installedApps().filter { $0.url != app.url }
        let otherVendors = Set(AppScanner.installedBundleIDs(others).compactMap(vendor))
        func exclusive(_ id: String) -> Bool {
            guard let v = vendor(id) else { return false }
            return !otherVendors.contains(v) && v != "com.apple"
        }

        // The app's own ID, plus the helpers shipped inside it (their files
        // are named after the helper) when no other app shares the developer.
        let mainID = app.bundleID?.lowercased()
        var needles = AppScanner.installedBundleIDs([app])
            .subtracting(AppScanner.installedBundleIDs([]))
            .filter { id in exclusive(id) || mainID.map { id.hasPrefix($0 + ".") } == true }
        if let mainID { needles.insert(mainID) }

        // Files named after the developer (com.vendor.Other) count too, again
        // only when nothing else installed is from that developer.
        let vendors = Set(needles.filter(exclusive).compactMap(vendor))

        let appName = app.name.lowercased()
        let fileName = app.url.deletingPathExtension().lastPathComponent.lowercased()
        let names: Set<String> = app.bundleID?.lowercased().hasPrefix("com.apple.") == true
            ? [] : Set([appName, fileName]).filter { $0.count >= 3 }
        // "BlueStacks" also owns com.bluestacks.appplayer.plist even when its
        // own ID is registered under a different developer name.
        let compactNames = Set(names.map { $0.filter { $0.isLetter || $0.isNumber } }.filter { $0.count >= 5 })
        var items: [RemovalItem] = []
        var seen = Set<String>()

        for loc in uninstallLocations where FileUtils.exists(loc.url) {
            progress?("Scanning \(loc.label)…")
            let isLibraryRoot = loc.label == "Library"
            for child in FileUtils.children(of: loc.url, includeHidden: true) {
                var entry = child.lastPathComponent.lowercased()
                if isLibraryRoot && standardLibraryFolders.contains(entry) { continue }
                // Group containers are "<TEAMID>.vendor.name" or "group.vendor.name".
                if let first = entry.split(separator: ".").first,
                   first.count == 10, first.allSatisfy({ $0.isLetter || $0.isNumber }),
                   first.contains(where: \.isNumber) {
                    entry = String(entry.dropFirst(first.count + 1))
                }
                for prefix in ["group.", "groups."] where entry.hasPrefix(prefix) {
                    entry = String(entry.dropFirst(prefix.count))
                }
                let matchesBundleID = needles.contains { entry == $0 || entry.hasPrefix($0 + ".") }
                var matchesVendor = vendors.contains { entry.hasPrefix($0 + ".") }
                // A guess by name alone: listed, but left unticked for review.
                var guessed = false
                if !matchesBundleID, !matchesVendor, !compactNames.isEmpty, exclusive(entry) {
                    guessed = entry.split(separator: ".").prefix(3).contains { compactNames.contains(String($0)) }
                    matchesVendor = guessed
                }
                // Name match only for folder-per-app locations, and only exact — avoids
                // e.g. "Slack" matching "Slack Helper Whatever".
                let matchesName = !loc.filePrefixMatch && names.contains(entry)
                guard matchesBundleID || matchesVendor || matchesName,
                      seen.insert(child.path).inserted else { continue }
                // Measuring can take a while for huge data folders (chat media,
                // browser profiles) — say what we're doing.
                progress?("Measuring \(child.lastPathComponent)…")
                items.append(RemovalItem(id: child.path, url: child,
                                         label: loc.label, size: FileUtils.size(of: child),
                                         selected: !guessed))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Reverse-DNS-looking entries in ~/Library that belong to no installed app → orphans.
    static func orphans(installedBundleIDs: Set<String>,
                        progress: ScanProgressReporter? = nil,
                        span: ClosedRange<Double> = 0...1) -> [RemovalItem] {
        // Vendors whose files we never flag: Apple's own, and ambiguous shared data.
        let protectedPrefixes = ["com.apple.", "group.com.apple.", "groups.com.apple.",
                                 "systemgroup.com.apple.", "is.workflow."]  // Shortcuts' legacy ID
        // Vendors (first two ID components) of everything installed.
        let installedVendors = Set(installedBundleIDs.map {
            $0.split(separator: ".").prefix(2).joined(separator: ".")
        })
        var items: [RemovalItem] = []
        let existing = locations.filter { FileUtils.exists($0.url) }
        let width = span.upperBound - span.lowerBound

        for (locIndex, loc) in existing.enumerated() {
            let children = FileUtils.children(of: loc.url, includeHidden: true)
            for (childIndex, child) in children.enumerated() {
                let step = (Double(locIndex) + Double(childIndex) / Double(max(children.count, 1)))
                    / Double(max(existing.count, 1))
                progress?.report(span.lowerBound + width * step,
                                 "Checking \(loc.label): \(child.lastPathComponent)")
                var entry = child.lastPathComponent.lowercased()
                for ext in [".plist", ".savedstate"] where entry.hasSuffix(ext) {
                    entry = String(entry.dropLast(ext.count))
                }
                // Group containers are "<TEAMID>.vendor.name", "group.vendor.name"
                // or both ("<TEAMID>.group.vendor.name") — strip those prefixes.
                if let first = entry.split(separator: ".").first,
                   first.count == 10, first.allSatisfy({ $0.isLetter || $0.isNumber }),
                   first.contains(where: \.isNumber) {
                    entry = String(entry.dropFirst(first.count + 1))
                }
                for prefix in ["group.", "groups."] where entry.hasPrefix(prefix) {
                    entry = String(entry.dropFirst(prefix.count))
                }
                // Only consider reverse-DNS names (at least vendor.tld.name) so we never
                // flag plain folders like "Firefox" whose ownership we can't prove.
                let parts = entry.split(separator: ".")
                guard parts.count >= 3 else { continue }
                guard !protectedPrefixes.contains(where: { entry.hasPrefix($0) }) else { continue }
                var owned = installedBundleIDs.contains { entry == $0 || entry.hasPrefix($0 + ".") }
                // Sparkle (the common updater framework) names its helpers'
                // data "<host vendor>.sparkle-project.…" — owned if any
                // installed app shares that vendor prefix.
                if !owned, let range = entry.range(of: ".sparkle-project.") {
                    let vendor = String(entry[..<range.lowerBound])
                    owned = installedBundleIDs.contains { $0.hasPrefix(vendor + ".") }
                }
                // Same developer as something installed → treat as shared data
                // (updaters, helpers, group containers). Deliberately cautious:
                // missing a leftover beats flagging live data.
                if !owned {
                    let vendor = entry.split(separator: ".").prefix(2).joined(separator: ".")
                    owned = installedVendors.contains(vendor)
                }
                guard !owned else { continue }
                let fraction = span.lowerBound + width * step
                progress?.report(fraction, "Measuring \(child.lastPathComponent)…", force: true)
                let size = FileUtils.size(of: child) { bytes, files in
                    progress?.report(fraction, "Measuring \(child.lastPathComponent) — \(Format.bytes(bytes)) so far (\(files.formatted()) files)")
                }
                items.append(RemovalItem(id: child.path, url: child, label: loc.label,
                                         size: size, selected: false))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}
