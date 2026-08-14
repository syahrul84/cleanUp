import Foundation
import AppKit

// MARK: - Models

enum HealthStatus {
    case good, warn, bad, info
    var color: NSColor {
        switch self {
        case .good: return .systemGreen
        case .warn: return .systemOrange
        case .bad: return .systemRed
        case .info: return .systemGray
        }
    }
}

struct HealthCheck: Identifiable {
    let id: String
    let icon: String
    let title: String
    let status: HealthStatus
    let detail: String
    var goTo: Feature? = nil   // deep link to another tab that fixes it
}

struct ProcInfo: Identifiable {
    let id: Int32              // pid
    let name: String
    let cpuPercent: Double
    let memBytes: Int64
    var icon: NSImage? {
        NSRunningApplication(processIdentifier: id)?.icon
    }
}

struct Tweak: Identifiable {
    let id: String
    let title: String
    let detail: String
    let isOn: () -> Bool
    let set: (Bool) -> Void
}

// MARK: - Service

enum SpeedService {

    // MARK: Health checklist

    static func healthChecks() -> [HealthCheck] {
        var checks: [HealthCheck] = []

        // Disk headroom — low free space genuinely slows APFS and swapping.
        let root = URL(fileURLWithPath: "/")
        let vals = try? root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = vals?.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(vals?.volumeTotalCapacity ?? 1)
        let freePct = Double(free) / Double(max(total, 1)) * 100
        checks.append(HealthCheck(
            id: "disk", icon: "internaldrive",
            title: "Disk headroom",
            status: freePct > 15 ? .good : freePct > 8 ? .warn : .bad,
            detail: String(format: "%@ free (%.0f%%). Below ~15%% macOS slows down.",
                           Format.bytes(free), freePct),
            goTo: freePct > 15 ? nil : .smartScan))

        // Swap usage — heavy swap means real memory pressure.
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        let swapUsed = Int64(swap.xsu_used)
        checks.append(HealthCheck(
            id: "swap", icon: "memorychip",
            title: "Memory pressure (swap in use)",
            status: swapUsed < 1 << 30 ? .good : swapUsed < 4 << 30 ? .warn : .bad,
            detail: swapUsed == 0
                ? "No swap in use — plenty of RAM available."
                : "\(Format.bytes(swapUsed)) swapped to disk. Quitting memory-hungry apps (below) or restarting helps."))

        // Startup items.
        let agents = StartupScanner.scan().filter { $0.scope == .userAgent && $0.enabled }
        checks.append(HealthCheck(
            id: "startup", icon: "power",
            title: "Startup items",
            status: agents.count <= 5 ? .good : agents.count <= 12 ? .warn : .bad,
            detail: "\(agents.count) launch agents start automatically. Fewer means faster login.",
            goTo: agents.count <= 5 ? nil : .startupItems))

        // Uptime.
        let days = Int(ProcessInfo.processInfo.systemUptime / 86_400)
        checks.append(HealthCheck(
            id: "uptime", icon: "clock.arrow.circlepath",
            title: "Time since last restart",
            status: days < 14 ? .good : days < 30 ? .warn : .bad,
            detail: days == 0 ? "Restarted today."
                : "\(days) day\(days == 1 ? "" : "s"). An occasional restart clears leaked memory and wedged processes."))

        return checks
    }

    // MARK: Resource hogs

    static func topProcesses(count: Int = 5) -> (cpu: [ProcInfo], mem: [ProcInfo]) {
        let (status, output) = run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"])
        guard status == 0 else { return ([], []) }
        var procs: [ProcInfo] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Int64(parts[2]) else { continue }
            let name = parts[3...].joined(separator: " ")
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            procs.append(ProcInfo(id: pid, name: name, cpuPercent: cpu, memBytes: rssKB * 1024))
        }
        let byCPU = Array(procs.filter { $0.cpuPercent >= 0.5 }.prefix(count))
        let byMem = Array(procs.sorted { $0.memBytes > $1.memBytes }.prefix(count))
        return (byCPU, byMem)
    }

    /// Names of processes currently preventing sleep.
    static func sleepBlockers() -> [String] {
        let (_, output) = run("/usr/bin/pmset", ["-g", "assertions"])
        var names = Set<String>()
        for line in output.split(separator: "\n")
        where line.contains("PreventUserIdleSystemSleep") || line.contains("PreventUserIdleDisplaySleep") {
            // e.g. `  pid 476(Music): [0x…] 00:01:02 PreventUserIdleSystemSleep named: …`
            if let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"),
               open < close, line.contains("pid ") {
                names.insert(String(line[line.index(after: open)..<close]))
            }
        }
        return names.sorted()
    }

    /// Politely quit a process. Returns an error message, or nil on success.
    static func quit(_ proc: ProcInfo) -> String? {
        if let app = NSRunningApplication(processIdentifier: proc.id) {
            return app.terminate() ? nil : "\(proc.name) declined to quit — it may have unsaved work."
        }
        return kill(proc.id, SIGTERM) == 0 ? nil
            : "Could not quit \(proc.name) (it may belong to the system)."
    }

    // MARK: Snappiness tweaks (all reversible; honest "feels faster" only)

    static let tweaks: [Tweak] = [
        Tweak(id: "dock-delay",
              title: "Instant Dock reveal",
              detail: "Removes the delay before an auto-hidden Dock slides out.",
              isOn: { defaultsRead("com.apple.dock", "autohide-delay") == "0" },
              set: { on in
                  if on {
                      defaultsWrite("com.apple.dock", "autohide-delay", ["-float", "0"])
                      defaultsWrite("com.apple.dock", "autohide-time-modifier", ["-float", "0.4"])
                  } else {
                      defaultsDelete("com.apple.dock", "autohide-delay")
                      defaultsDelete("com.apple.dock", "autohide-time-modifier")
                  }
                  restartDock()
              }),
        Tweak(id: "mission-control",
              title: "Faster Mission Control",
              detail: "Shortens the Mission Control zoom animation.",
              isOn: { defaultsRead("com.apple.dock", "expose-animation-duration") != nil },
              set: { on in
                  if on {
                      defaultsWrite("com.apple.dock", "expose-animation-duration", ["-float", "0.12"])
                  } else {
                      defaultsDelete("com.apple.dock", "expose-animation-duration")
                  }
                  restartDock()
              }),
        Tweak(id: "window-anim",
              title: "Skip window open/close animation",
              detail: "New windows appear immediately. Applies to apps launched afterwards.",
              isOn: { defaultsRead(nil, "NSAutomaticWindowAnimationsEnabled") == "0" },
              set: { on in
                  if on {
                      defaultsWrite(nil, "NSAutomaticWindowAnimationsEnabled", ["-bool", "false"])
                  } else {
                      defaultsDelete(nil, "NSAutomaticWindowAnimationsEnabled")
                  }
              }),
        Tweak(id: "resize-time",
              title: "Instant window resize in dialogs",
              detail: "Removes the grow/shrink animation some panels use.",
              isOn: { defaultsRead(nil, "NSWindowResizeTime") != nil },
              set: { on in
                  if on {
                      defaultsWrite(nil, "NSWindowResizeTime", ["-float", "0.001"])
                  } else {
                      defaultsDelete(nil, "NSWindowResizeTime")
                  }
              }),
    ]

    static func restoreAllTweaks() {
        defaultsDelete("com.apple.dock", "autohide-delay")
        defaultsDelete("com.apple.dock", "autohide-time-modifier")
        defaultsDelete("com.apple.dock", "expose-animation-duration")
        defaultsDelete(nil, "NSAutomaticWindowAnimationsEnabled")
        defaultsDelete(nil, "NSWindowResizeTime")
        restartDock()
    }

    // MARK: Maintenance

    static func restartFinder() { run("/usr/bin/killall", ["Finder"]) }
    static func restartDock() { run("/usr/bin/killall", ["Dock"]) }

    /// Flush the DNS cache. Prompts for the admin password via the standard
    /// macOS authorization dialog. Returns an error message, or nil on success.
    static func flushDNS() -> String? {
        runAdmin("dscacheutil -flushcache; killall -HUP mDNSResponder")
    }

    /// Ask Spotlight to re-import a folder's contents (user-level, no admin).
    static func reindex(folder: URL) -> String? {
        let (status, output) = run("/usr/bin/mdimport", ["-i", folder.path])
        return status == 0 ? nil : output
    }

    // MARK: Helpers

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func runAdmin(_ shell: String) -> String? {
        let source = "do shell script \"\(shell)\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        return errorInfo?[NSAppleScript.errorMessage] as? String
    }

    private static func defaultsRead(_ domain: String?, _ key: String) -> String? {
        let (status, output) = run("/usr/bin/defaults", ["read", domain ?? "-g", key])
        return status == 0 ? output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    private static func defaultsWrite(_ domain: String?, _ key: String, _ value: [String]) {
        run("/usr/bin/defaults", ["write", domain ?? "-g", key] + value)
    }

    private static func defaultsDelete(_ domain: String?, _ key: String) {
        run("/usr/bin/defaults", ["delete", domain ?? "-g", key])
    }
}
