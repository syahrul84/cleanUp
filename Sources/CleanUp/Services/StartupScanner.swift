import Foundation

struct StartupItem: Identifiable {
    enum Scope: String {
        case userAgent = "Your Launch Agents"
        case systemAgent = "System-wide Launch Agents"
        case systemDaemon = "Launch Daemons"
    }

    let id: String            // plist path
    let url: URL
    let label: String
    let program: String
    let scope: Scope
    var enabled: Bool         // false = plist parked in the Disabled folder
}

/// Lists launchd startup items and can enable/disable the user's own agents.
/// Disabling = launchctl bootout + moving the plist into a "Disabled" folder,
/// so it is always reversible.
enum StartupScanner {

    static var userAgentsDir: URL {
        FileUtils.home.appendingPathComponent("Library/LaunchAgents")
    }
    static var disabledDir: URL {
        FileUtils.home.appendingPathComponent("Library/LaunchAgents (Disabled)")
    }

    static func scan() -> [StartupItem] {
        var items: [StartupItem] = []
        items += read(dir: userAgentsDir, scope: .userAgent, enabled: true)
        items += read(dir: disabledDir, scope: .userAgent, enabled: false)
        items += read(dir: URL(fileURLWithPath: "/Library/LaunchAgents"), scope: .systemAgent, enabled: true)
        items += read(dir: URL(fileURLWithPath: "/Library/LaunchDaemons"), scope: .systemDaemon, enabled: true)
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private static func read(dir: URL, scope: StartupItem.Scope, enabled: Bool) -> [StartupItem] {
        FileUtils.children(of: dir)
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                let dict = NSDictionary(contentsOf: url)
                let label = dict?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = dict?["Program"] as? String
                    ?? (dict?["ProgramArguments"] as? [String])?.first
                    ?? "—"
                return StartupItem(id: url.path, url: url, label: label,
                                   program: program, scope: scope, enabled: enabled)
            }
    }

    /// Disable a user launch agent. Returns an error message, or nil on success.
    static func disable(_ item: StartupItem) -> String? {
        launchctl(["bootout", "gui/\(getuid())/\(item.label)"]) // best effort; may not be loaded
        do {
            try FileManager.default.createDirectory(at: disabledDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(
                at: item.url, to: disabledDir.appendingPathComponent(item.url.lastPathComponent))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Re-enable a previously disabled user launch agent.
    static func enable(_ item: StartupItem) -> String? {
        let target = userAgentsDir.appendingPathComponent(item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
        } catch {
            return error.localizedDescription
        }
        launchctl(["bootstrap", "gui/\(getuid())", target.path])
        return nil
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
