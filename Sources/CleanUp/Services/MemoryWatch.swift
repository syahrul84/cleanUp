import Foundation
import AppKit
import UserNotifications
import Darwin

struct WatchedApp: Identifiable {
    let id: String            // bundle identifier (or "pid:N" fallback)
    let pid: pid_t
    let name: String
    let icon: NSImage?
    var footprint: Int64      // physical memory footprint (what Activity Monitor shows)
    var threshold: Int64?     // nil = "Default" — macOS manages it, no alerts
    var isOver: Bool { threshold.map { footprint >= $0 } ?? false }
}

/// Watches running apps' memory footprints. macOS cannot hard-cap an app's
/// memory, so this is an honest watchdog instead: the user sets a per-app
/// alert level, and crossing it fires a notification with Quit / Relaunch
/// actions. Thresholds persist across launches keyed by bundle ID.
final class MemoryWatch: ObservableObject {
    static let shared = MemoryWatch()

    @Published private(set) var apps: [WatchedApp] = []
    @Published var notificationsDenied = false

    static let notificationCategory = "MEMORY_ALERT"
    private static let defaultsKey = "memoryWatch.thresholds"

    private var timer: Timer?
    private var overIDs: Set<String> = []      // currently above threshold (already alerted)
    private var lastAlert: [String: Date] = [:]

    /// Threshold choices offered in the UI (bytes).
    static let thresholdOptions: [Int64] = [
        512 << 20,
        1 << 30, 2 << 30, 3 << 30, 4 << 30, 6 << 30, 8 << 30, 12 << 30, 16 << 30,
    ]

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        registerNotificationCategory()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    // MARK: - Thresholds

    private var storedThresholds: [String: Int64] {
        get {
            (UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Any])?
                .compactMapValues { ($0 as? NSNumber)?.int64Value } ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue as [String: NSNumber], forKey: Self.defaultsKey)
        }
    }

    func setThreshold(_ bytes: Int64?, for appID: String) {
        var thresholds = storedThresholds
        if let bytes {
            thresholds[appID] = bytes
            requestNotificationPermission()
        } else {
            thresholds.removeValue(forKey: appID)
        }
        storedThresholds = thresholds
        overIDs.remove(appID)
        sample()
    }

    // MARK: - Sampling

    private func sample() {
        let stored = storedThresholds
        var result: [WatchedApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            let id = app.bundleIdentifier ?? "pid:\(pid)"
            let entry = WatchedApp(id: id, pid: pid,
                                   name: app.localizedName ?? id,
                                   icon: app.icon,
                                   footprint: Self.footprint(pid: pid),
                                   threshold: stored[id])
            result.append(entry)
            evaluateAlert(entry)
        }
        result.sort {
            if $0.isOver != $1.isOver { return $0.isOver }
            return $0.footprint > $1.footprint
        }
        apps = result
    }

    /// Physical footprint of a process — the same figure Activity Monitor's
    /// Memory column shows. Works for the user's own processes.
    static func footprint(pid: pid_t) -> Int64 {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        return result == 0 ? Int64(usage.ri_phys_footprint) : 0
    }

    // MARK: - Alerts

    private func evaluateAlert(_ app: WatchedApp) {
        guard let threshold = app.threshold else {
            overIDs.remove(app.id)
            return
        }
        if app.footprint >= threshold {
            let coolingDown = lastAlert[app.id].map { Date().timeIntervalSince($0) < 300 } ?? false
            if !overIDs.contains(app.id) && !coolingDown {
                overIDs.insert(app.id)
                lastAlert[app.id] = Date()
                postAlert(app, threshold: threshold)
            }
        } else if app.footprint < Int64(Double(threshold) * 0.9) {
            // Re-arm once usage drops clearly below the threshold.
            overIDs.remove(app.id)
        }
    }

    private func postAlert(_ app: WatchedApp, threshold: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "\(app.name) is using \(Format.bytes(app.footprint))"
        content.body = "That's above your \(Format.bytes(threshold)) alert level. Quit or relaunch it to free memory."
        content.categoryIdentifier = Self.notificationCategory
        content.sound = .default
        content.userInfo = ["pid": Int(app.pid), "bundleID": app.id]
        let request = UNNotificationRequest(
            identifier: "memwatch-\(app.id)-\(Int(Date().timeIntervalSince1970))",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func registerNotificationCategory() {
        let quit = UNNotificationAction(identifier: "QUIT_APP", title: "Quit App",
                                        options: [.destructive])
        let relaunch = UNNotificationAction(identifier: "RELAUNCH_APP", title: "Relaunch App",
                                            options: [])
        let category = UNNotificationCategory(identifier: Self.notificationCategory,
                                              actions: [quit, relaunch],
                                              intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.notificationsDenied = !granted }
        }
    }

    // MARK: - Notification actions

    static func handleAction(_ identifier: String, userInfo: [AnyHashable: Any]) {
        let pid = (userInfo["pid"] as? Int).map(pid_t.init)
        let bundleID = userInfo["bundleID"] as? String
        let app = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier == pid
                || ($0.bundleIdentifier != nil && $0.bundleIdentifier == bundleID)
        }
        switch identifier {
        case "QUIT_APP":
            app?.terminate()
        case "RELAUNCH_APP":
            guard let app, let url = app.bundleURL else { return }
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSWorkspace.shared.openApplication(at: url,
                                                   configuration: NSWorkspace.OpenConfiguration())
            }
        default:
            break
        }
    }
}
