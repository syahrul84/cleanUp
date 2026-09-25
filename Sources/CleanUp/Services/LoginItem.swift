import Foundation
import ServiceManagement

/// Wraps SMAppService registration so the app (and its menu bar widget)
/// can start automatically at login.
final class LoginItem: ObservableObject {
    @Published var enabled = false
    @Published var lastError: String?
    /// True when macOS wants the user to approve CleanUp in System Settings.
    @Published var needsApproval = false

    init() { refresh() }

    /// Re-read the real state from macOS (the panel calls this on open).
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            let status = service.status
            // Already in the requested state: registering an enabled item or
            // unregistering a missing one can throw even though all is well.
            if (on && status == .enabled) || (!on && status == .notRegistered) {
                lastError = nil
            } else if on && status == .requiresApproval {
                lastError = "macOS needs your OK: switch CleanUp on under System Settings → General → Login Items."
            } else {
                let e = error as NSError
                lastError = "Couldn't change Launch at login: \(e.localizedDescription) (\(e.domain) \(e.code))"
            }
            Self.log("set(\(on)) failed: \(error) — status now \(status.rawValue)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Diagnostics for support: ~/Library/Logs/CleanUp/CleanUp.log
    static func log(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CleanUp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("CleanUp.log")
        let line = "\(Date().formatted(.iso8601)) [LoginItem] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}
