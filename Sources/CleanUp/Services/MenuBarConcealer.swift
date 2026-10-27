import AppKit
import ApplicationServices
import ObjectiveC

/// macOS 27+ menu bar hiding. macOS 27 draws the whole menu bar itself, so
/// the old "very wide separator" trick no longer hides anything. Instead we
/// use the private MenuBarClientCore "assessment mode" assertion: an
/// allowlist of apps whose icons may be shown — everything else is hidden by
/// the system. Undocumented, so every step fails safe: if anything is
/// missing, nothing is hidden.
final class MenuBarConcealer {
    static let shared = MenuBarConcealer()

    static var isNeeded: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    var isAvailable: Bool { configClass != nil && assertionClass != nil }

    private let configClass: NSObject.Type?
    private let assertionClass: NSObject.Type?
    private var current: NSObject?
    private var launchObserver: NSObjectProtocol?
    private var hiddenIDs: Set<String> = []

    private init() {
        dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW)
        configClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type
        assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
    }

    /// Hide the icons of `hidden` apps; everything else stays visible.
    func conceal(hiding hidden: Set<String>) {
        hiddenIDs = hidden
        apply()
        if launchObserver == nil {
            // Newly launched apps aren't on the allowlist yet — refresh so
            // their icons don't vanish unexpectedly.
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.current != nil else { return }
                self.apply()
            }
        }
    }

    func reveal() {
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        invalidate(current)
        current = nil
    }

    private func apply() {
        guard let configClass, let assertionClass, !hiddenIDs.isEmpty else { reveal(); return }
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        allowed.subtract(hiddenIDs)
        if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
        // System items (clock, Wi-Fi, battery, Control Center…) are numbered;
        // numbers with no item behind them are ignored, so allow them all.
        let systemItems = (0...255).map { NSNumber(value: $0) }

        typealias InitConfig = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> AnyObject
        let initSel = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
        guard class_respondsToSelector(configClass, initSel),
              let initIMP = class_getMethodImplementation(configClass, initSel) else { return }
        let raw = configClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        let config = unsafeBitCast(initIMP, to: InitConfig.self)(raw, initSel, systemItems as NSArray,
                                                                 Array(allowed) as NSArray)

        typealias Activate = @convention(c) (AnyObject, Selector, AnyObject,
                                             @escaping @convention(block) (NSError?) -> Void) -> Void
        let activateSel = NSSelectorFromString("activateWithConfiguration:completionHandler:")
        guard class_respondsToSelector(assertionClass, activateSel),
              let activateIMP = class_getMethodImplementation(assertionClass, activateSel) else { return }
        let next = assertionClass.init()
        let previous = current
        current = next
        // Activate the new allowlist before dropping the old one, so icons
        // don't flash back in between.
        unsafeBitCast(activateIMP, to: Activate.self)(next, activateSel, config) { [weak self] error in
            DispatchQueue.main.async {
                self?.invalidate(previous)
                if let error { LoginItem.log("Menu bar concealment failed: \(error)") }
            }
        }
    }

    private func invalidate(_ assertion: NSObject?) {
        let sel = NSSelectorFromString("invalidate")
        if let assertion, assertion.responds(to: sel) { assertion.perform(sel) }
    }

    // MARK: - Which apps have menu bar icons

    struct MenuBarApp: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage?
        var id: String { bundleID }
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Running apps that own at least one menu bar icon (needs Accessibility).
    static func appsWithMenuBarIcons() -> [MenuBarApp] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, id != own else { return nil }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success,
                  let bar = value else { return nil }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString,
                                                &children) == .success,
                  let list = children as? [AnyObject], !list.isEmpty else { return nil }
            return MenuBarApp(bundleID: id, name: app.localizedName ?? id, icon: app.icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
