import Foundation
import ServiceManagement

/// Wraps SMAppService registration so the app (and its menu bar widget)
/// can start automatically at login.
final class LoginItem: ObservableObject {
    @Published var enabled: Bool = SMAppService.mainApp.status == .enabled
    @Published var lastError: String?

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
