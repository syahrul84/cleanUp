import Foundation
import AppKit

struct BrewPackage: Identifiable {
    let name: String
    let isCask: Bool
    var size: Int64?
    var icon: NSImage?    // installed app's real icon (casks only)
    var id: String { (isCask ? "cask:" : "formula:") + name }
}

struct DiscoverCask: Identifiable {
    let token: String
    let displayName: String
    let desc: String
    let homepage: String
    var id: String { token }
}

struct AdoptableApp: Identifiable {
    let name: String
    let appPath: String
    let caskToken: String
    let autoUpdates: Bool
    let icon: NSImage
    var id: String { appPath }
}

struct BrewOutdated: Identifiable {
    let name: String
    let installed: String
    let latest: String
    let isCask: Bool
    var id: String { (isCask ? "cask:" : "formula:") + name }
}

/// Maintenance-scoped Homebrew integration: everything shells out to the
/// user's own `brew` executable. No installs/search — cleanup, orphan
/// removal, package updates and uninstalls only.
final class HomebrewService: ObservableObject {
    static let shared = HomebrewService()

    @Published var available = false
    @Published var scanning = false
    @Published var installed: [BrewPackage] = []
    @Published var orphans: [String] = []
    @Published var outdated: [BrewOutdated] = []
    @Published var cleanupEstimate: String?   // e.g. "1.2GB" — nil when nothing to clean
    @Published var adoptable: [AdoptableApp] = []
    @Published var catalog: [DiscoverCask] = []           // full cask catalog for local search
    @Published var popular: [DiscoverCask] = []           // top installs, not yet installed
    @Published var installedCaskTokens: Set<String> = []
    @Published var catalogUnavailable = false
    @Published var busyTitle: String?          // non-nil while a brew action runs
    @Published var log = ""
    @Published var terminalFallback: String?   // brew command needing an admin password

    private let queue = DispatchQueue(label: "homebrew", qos: .userInitiated)
    private var rescanQueued = false // main-thread only

    var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var prefix: URL? {
        brewPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent() }
    }

    // MARK: - Scanning

    func scan() {
        guard let brew = brewPath else {
            available = false
            return
        }
        available = true
        guard !scanning, busyTitle == nil else {
            rescanQueued = true // don't drop refreshes that arrive mid-scan
            return
        }
        scanning = true

        queue.async { [self] in
            // Installed packages (names first, sizes filled in below).
            let formulae = runQuiet(brew, ["list", "-1", "--formula"]).lines
            let casks = runQuiet(brew, ["list", "-1", "--cask"]).lines
            var packages = formulae.map { BrewPackage(name: $0, isCask: false) }
                + casks.map { BrewPackage(name: $0, isCask: true) }
            packages.sort { $0.name < $1.name }
            publish { self.installed = packages }

            // Orphaned dependencies.
            let autoremoveOut = runQuiet(brew, ["autoremove", "-n"]).output
            let orphanNames = autoremoveOut
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("==>") && !$0.contains(" ") }
            publish { self.orphans = orphanNames }

            // Cleanup estimate.
            let cleanupOut = runQuiet(brew, ["cleanup", "-n"]).output
            var estimate: String?
            if let range = cleanupOut.range(of: #"approximately (.+?) of disk space"#,
                                            options: .regularExpression) {
                estimate = String(cleanupOut[range])
                    .replacingOccurrences(of: "approximately ", with: "")
                    .replacingOccurrences(of: " of disk space", with: "")
            } else if cleanupOut.contains("Would remove") {
                estimate = "some space"
            }
            publish { self.cleanupEstimate = estimate }

            // Outdated packages.
            let outdatedJSON = runQuiet(brew, ["outdated", "--json=v2"]).output
            publish { self.outdated = Self.parseOutdated(outdatedJSON) }

            // Manually-installed apps that Homebrew could adopt.
            let adoptableApps = computeAdoptable()
            publish { self.adoptable = adoptableApps }

            // Discover: searchable catalog + popular casks.
            let tokens = self.installedTokens()
            let fullCatalog = self.parsedCatalog()
            let popularCasks = self.computePopular(catalog: fullCatalog, installed: tokens)
            publish {
                self.installedCaskTokens = tokens
                self.catalog = fullCatalog
                self.popular = popularCasks
                self.catalogUnavailable = fullCatalog.isEmpty
            }

            // Real icons for installed cask apps (needs the catalog's mapping).
            var icons: [(id: String, icon: NSImage)] = []
            for package in packages where package.isCask {
                if let appName = tokenAppNameMemo?[package.name] {
                    let path = "/Applications/\(appName)"
                    if FileManager.default.fileExists(atPath: path) {
                        let icon = NSWorkspace.shared.icon(forFile: path)
                        icon.size = NSSize(width: 32, height: 32)
                        icons.append((package.id, icon))
                    }
                }
            }
            let resolved = icons
            publish {
                for (id, icon) in resolved {
                    if let idx = self.installed.firstIndex(where: { $0.id == id }) {
                        self.installed[idx].icon = icon
                    }
                }
            }

            // Package sizes from the Cellar/Caskroom, filled progressively.
            if let prefix = self.prefix {
                for package in packages {
                    let dir = prefix
                        .appendingPathComponent(package.isCask ? "Caskroom" : "Cellar")
                        .appendingPathComponent(package.name)
                    let size = FileUtils.size(of: dir)
                    publish {
                        if let idx = self.installed.firstIndex(where: { $0.id == package.id }) {
                            self.installed[idx].size = size
                        }
                    }
                }
            }
            publish {
                self.scanning = false
                if self.rescanQueued {
                    self.rescanQueued = false
                    self.scan()
                }
            }
        }
    }

    private static func parseOutdated(_ json: String) -> [BrewOutdated] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var result: [BrewOutdated] = []
        for (key, isCask) in [("formulae", false), ("casks", true)] {
            for entry in root[key] as? [[String: Any]] ?? [] {
                guard let name = entry["name"] as? String else { continue }
                let installed = (entry["installed_versions"] as? [String])?.last
                    ?? entry["installed_versions"] as? String ?? "?"
                let latest = entry["current_version"] as? String ?? "?"
                result.append(BrewOutdated(name: name, installed: installed,
                                           latest: latest, isCask: isCask))
            }
        }
        return result
    }

    // MARK: - Cask adoption

    private struct CaskCandidate {
        let token: String
        let autoUpdates: Bool
    }

    /// "Name.app" → matching casks, built from Homebrew's public catalog API.
    private var caskIndexMemo: [String: [CaskCandidate]]?

    private var caskCacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("CleanUp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cask-catalog.json")
    }

    /// JSON from formulae.brew.sh: disk cache (fresh 3 days) → network → stale cache.
    private func cachedFetch(_ urlString: String, cacheName: String) -> Data? {
        let cache = caskCacheURL.deletingLastPathComponent().appendingPathComponent(cacheName)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 3 * 86_400,
           let data = try? Data(contentsOf: cache) {
            return data
        }
        var request = URLRequest(url: URL(string: urlString)!)
        request.timeoutInterval = 30
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { fetched = data }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let fetched {
            try? fetched.write(to: cache)
            return fetched
        }
        return try? Data(contentsOf: cache) // stale is better than nothing
    }

    private func caskCatalogData() -> Data? {
        cachedFetch("https://formulae.brew.sh/api/cask.json", cacheName: "cask-catalog.json")
    }

    private var catalogMemo: [DiscoverCask]?
    private var tokenAppNameMemo: [String: String]?   // cask token → "Name.app"

    /// One parse pass builds both the app-name index (adoption) and the
    /// searchable catalog (discover).
    private func parseCatalogIfNeeded() {
        guard caskIndexMemo == nil || catalogMemo == nil else { return }
        guard let data = caskCatalogData(),
              let casks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }
        var index: [String: [CaskCandidate]] = [:]
        var entries: [DiscoverCask] = []
        var tokenApp: [String: String] = [:]
        for cask in casks {
            guard let token = cask["token"] as? String else { continue }
            let auto = cask["auto_updates"] as? Bool ?? false
            var shipsApp = false
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                for entry in artifact["app"] as? [Any] ?? [] {
                    if let name = entry as? String, name.hasSuffix(".app") {
                        shipsApp = true
                        if tokenApp[token] == nil { tokenApp[token] = name }
                        index[name, default: []].append(CaskCandidate(token: token, autoUpdates: auto))
                    }
                }
            }
            // Discover lists GUI apps only — casks that actually ship a .app.
            if shipsApp {
                let display = (cask["name"] as? [String])?.first ?? token
                entries.append(DiscoverCask(token: token, displayName: display,
                                            desc: cask["desc"] as? String ?? "",
                                            homepage: cask["homepage"] as? String ?? ""))
            }
        }
        caskIndexMemo = index
        catalogMemo = entries
        tokenAppNameMemo = tokenApp
    }

    private func caskIndex() -> [String: [CaskCandidate]] {
        parseCatalogIfNeeded()
        return caskIndexMemo ?? [:]
    }

    private func parsedCatalog() -> [DiscoverCask] {
        parseCatalogIfNeeded()
        return catalogMemo ?? []
    }

    func installedTokens() -> Set<String> {
        guard let prefix else { return [] }
        return Set(FileUtils.children(of: prefix.appendingPathComponent("Caskroom"))
            .map { $0.lastPathComponent })
    }

    /// Top casks by Homebrew's public 30-day install analytics, GUI apps only,
    /// excluding what's already installed.
    private func computePopular(catalog: [DiscoverCask], installed: Set<String>) -> [DiscoverCask] {
        guard let data = cachedFetch("https://formulae.brew.sh/api/analytics/cask-install/30d.json",
                                     cacheName: "cask-analytics.json"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            return []
        }
        let byToken = Dictionary(uniqueKeysWithValues: catalog.map { ($0.token, $0) })
        var result: [DiscoverCask] = []
        for item in items {
            guard result.count < 20 else { break }
            guard let token = item["cask"] as? String,
                  !installed.contains(token),
                  let entry = byToken[token] else { continue }
            result.append(entry)
        }
        return result
    }

    /// Apps in /Applications that Homebrew could take over: not App Store,
    /// not already brew-managed, unambiguously matching one cask.
    private func computeAdoptable() -> [AdoptableApp] {
        let index = caskIndex()
        guard !index.isEmpty, let prefix else { return [] }
        let installedTokens = Set(FileUtils.children(of: prefix.appendingPathComponent("Caskroom"))
            .map { $0.lastPathComponent })

        var result: [AdoptableApp] = []
        for app in AppScanner.installedApps() {
            guard app.url.path.hasPrefix("/Applications/") else { continue }
            guard app.bundleID != Bundle.main.bundleIdentifier else { continue }
            let masReceipt = app.url.appendingPathComponent("Contents/_MASReceipt/receipt")
            guard !FileUtils.exists(masReceipt) else { continue }
            guard let candidates = index[app.url.lastPathComponent], !candidates.isEmpty else { continue }
            guard !candidates.contains(where: { installedTokens.contains($0.token) }) else { continue }

            let chosen: CaskCandidate
            if candidates.count == 1 {
                chosen = candidates[0]
            } else {
                // Same app name shipped by several casks — only proceed when the
                // token itself matches the app name; otherwise stay silent.
                let normalized = app.url.lastPathComponent.dropLast(4).lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                guard let exact = candidates.first(where: {
                    $0.token.replacingOccurrences(of: "-", with: "").lowercased() == normalized
                }) else { continue }
                chosen = exact
            }
            result.append(AdoptableApp(name: app.name, appPath: app.url.path,
                                       caskToken: chosen.token,
                                       autoUpdates: chosen.autoUpdates,
                                       icon: app.icon))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Actions (streamed into the log)

    func install(_ cask: DiscoverCask) {
        runStreaming(["install", "--cask", cask.token],
                     title: "Installing \(cask.displayName)…")
    }

    /// Open Terminal running the failed command, where sudo can prompt.
    func continueInTerminal() {
        guard let command = terminalFallback else { return }
        terminalFallback = nil
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    func adopt(_ app: AdoptableApp) {
        runStreaming(["install", "--cask", "--adopt", app.caskToken],
                     title: "Adopting \(app.name)…")
    }

    func adoptAll() {
        guard !adoptable.isEmpty else { return }
        runStreaming(["install", "--cask", "--adopt"] + adoptable.map(\.caskToken),
                     title: "Adopting \(adoptable.count) apps…")
    }


    func cleanUp() {
        runStreaming(["cleanup", "--prune=all"], title: "Cleaning up…")
    }

    func removeOrphans() {
        runStreaming(["autoremove"], title: "Removing orphaned dependencies…")
    }

    func upgradeAll() {
        runStreaming(["upgrade"], title: "Updating all packages…")
    }

    func upgrade(_ package: BrewOutdated) {
        runStreaming(package.isCask ? ["upgrade", "--cask", package.name]
                                    : ["upgrade", package.name],
                     title: "Updating \(package.name)…")
    }

    func uninstall(_ package: BrewPackage) {
        runStreaming(package.isCask ? ["uninstall", "--cask", package.name]
                                    : ["uninstall", package.name],
                     title: "Uninstalling \(package.name)…")
    }

    private func runStreaming(_ args: [String], title: String) {
        guard let brew = brewPath, busyTitle == nil else { return }
        busyTitle = title
        log = "$ brew \(args.joined(separator: " "))\n"

        queue.async { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["HOMEBREW_COLOR"] = "0"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
                self.publish { self.log += text }
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                publish { self.log += "\nFailed to run brew: \(error.localizedDescription)\n" }
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus
            publish {
                self.log += status == 0 ? "\n✓ Done\n" : "\n✗ brew exited with status \(status)\n"
                self.busyTitle = nil
                // Some casks run sudo (e.g. ownership fixes), which can only
                // prompt for a password in a real terminal.
                if status != 0, self.log.contains("sudo: a password is required")
                    || self.log.contains("terminal is required to read the password") {
                    self.terminalFallback = "brew " + args.joined(separator: " ")
                }
                // Instant feedback: drop freshly-managed casks from Adoptable
                // right away, even if a background scan is still running.
                let tokens = self.installedTokens()
                self.installedCaskTokens = tokens
                self.adoptable.removeAll { tokens.contains($0.caskToken) }
            }
            // Full refresh (queued automatically if a scan is mid-flight).
            publish { self.scan() }
        }
    }

    // MARK: - Helpers

    private struct RunResult {
        let output: String
        var lines: [String] {
            output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
    }

    private func runQuiet(_ brew: String, _ args: [String]) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_COLOR"] = "0"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // keep stderr noise out of parsed output
        do { try process.run() } catch { return RunResult(output: "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(output: String(data: data, encoding: .utf8) ?? "")
    }

    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}
