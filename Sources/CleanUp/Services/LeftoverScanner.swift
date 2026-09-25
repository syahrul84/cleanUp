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
    /// `progress` is called with a human-readable status as locations are
    /// scanned and large folders are measured.
    static func leftovers(for app: AppInfo,
                          progress: ((String) -> Void)? = nil) -> [RemovalItem] {
        var needles: [String] = []
        if let bid = app.bundleID?.lowercased() { needles.append(bid) }
        let appName = app.name.lowercased()
        var items: [RemovalItem] = []

        for loc in locations where FileUtils.exists(loc.url) {
            progress?("Scanning \(loc.label)…")
            for child in FileUtils.children(of: loc.url, includeHidden: true) {
                let entry = child.lastPathComponent.lowercased()
                let matchesBundleID = needles.contains { entry == $0 || entry.hasPrefix($0 + ".") }
                // Name match only for folder-per-app locations, and only exact — avoids
                // e.g. "Slack" matching "Slack Helper Whatever".
                let matchesName = !loc.filePrefixMatch && entry == appName
                guard matchesBundleID || matchesName else { continue }
                // Measuring can take a while for huge data folders (chat media,
                // browser profiles) — say what we're doing.
                progress?("Measuring \(child.lastPathComponent)…")
                items.append(RemovalItem(id: child.path, url: child,
                                         label: loc.label, size: FileUtils.size(of: child)))
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
