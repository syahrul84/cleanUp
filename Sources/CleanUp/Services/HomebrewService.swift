import Foundation
import AppKit

struct BrewPackage: Identifiable {
    let name: String
    let isCask: Bool
    var size: Int64?
    var id: String { (isCask ? "cask:" : "formula:") + name }
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
    @Published var busyTitle: String?          // non-nil while a brew action runs
    @Published var log = ""

    private let queue = DispatchQueue(label: "homebrew", qos: .userInitiated)

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
        guard !scanning, busyTitle == nil else { return }
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
            publish { self.scanning = false }
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

    // MARK: - Actions (streamed into the log)

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
            }
            // Refresh state after any action.
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
