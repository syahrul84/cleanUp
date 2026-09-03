import AppKit
import SwiftUI

/// Menu bar decluttering via the separator trick (the Hidden Bar / Ice
/// technique): CleanUp owns two status items — a separator mark and a
/// chevron toggle. The user ⌘-drags third-party icons to the LEFT of the
/// separator; collapsing inflates the separator's length so macOS itself
/// clips those icons out of the bar. macOS offers no API to control other
/// apps' status items directly — this is the only reliable, permission-free
/// way, and arrangement is inherently the user's one-time ⌘-drag.
final class MenuBarOrganizer: ObservableObject {
    static let shared = MenuBarOrganizer()

    @Published private(set) var enabled = false
    @Published private(set) var isCollapsed = false
    @Published var autoHideSeconds: Int {
        didSet { UserDefaults.standard.set(autoHideSeconds, forKey: "organizer.autoHide") }
    }
    @Published var startCollapsed: Bool {
        didSet { UserDefaults.standard.set(startCollapsed, forKey: "organizer.startCollapsed") }
    }

    private var chevronItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var autoHideTimer: Timer?

    private let collapsedLength: CGFloat = 10_000
    private let expandedLength: CGFloat = 14

    private init() {
        autoHideSeconds = UserDefaults.standard.integer(forKey: "organizer.autoHide")
        startCollapsed = UserDefaults.standard.object(forKey: "organizer.startCollapsed") as? Bool ?? true
    }

    /// Called at app launch.
    func start() {
        if UserDefaults.standard.bool(forKey: "organizer.enabled") {
            setEnabled(true, collapseNow: startCollapsed)
        }
    }

    func setEnabled(_ on: Bool, collapseNow: Bool = false) {
        UserDefaults.standard.set(on, forKey: "organizer.enabled")
        enabled = on
        if on {
            buildItems()
            collapseNow ? collapse() : expand()
        } else {
            autoHideTimer?.invalidate()
            if let chevronItem { NSStatusBar.system.removeStatusItem(chevronItem) }
            if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
            chevronItem = nil
            separatorItem = nil
            isCollapsed = false
        }
    }

    func toggleCollapsed() {
        isCollapsed ? expand() : collapse()
    }

    func collapse() {
        guard enabled else { return }
        autoHideTimer?.invalidate()
        separatorItem?.length = collapsedLength
        separatorItem?.button?.image = nil
        chevronItem?.button?.image = chevronImage(collapsed: true)
        isCollapsed = true
    }

    func expand() {
        guard enabled else { return }
        separatorItem?.length = expandedLength
        separatorItem?.button?.image = separatorImage()
        chevronItem?.button?.image = chevronImage(collapsed: false)
        isCollapsed = false

        autoHideTimer?.invalidate()
        if autoHideSeconds > 0 {
            autoHideTimer = Timer.scheduledTimer(withTimeInterval: Double(autoHideSeconds),
                                                 repeats: false) { [weak self] _ in
                self?.collapse()
            }
        }
    }

    // MARK: - Items

    private func buildItems() {
        guard chevronItem == nil else { return }

        // Chevron first so it sits to the RIGHT of the separator by default
        // (new status items are inserted to the left of existing ones).
        let chevron = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        chevron.autosaveName = "cleanup.organizer.chevron"
        chevron.behavior = []
        chevron.button?.image = chevronImage(collapsed: false)
        chevron.button?.target = self
        chevron.button?.action = #selector(chevronClicked)
        chevron.button?.toolTip = "CleanUp — show or hide menu bar icons"
        chevronItem = chevron

        let separator = NSStatusBar.system.statusItem(withLength: expandedLength)
        separator.autosaveName = "cleanup.organizer.separator"
        separator.button?.image = separatorImage()
        separator.button?.toolTip = "CleanUp separator — ⌘-drag icons to the left of me to make them hideable"
        separatorItem = separator
    }

    @objc private func chevronClicked() {
        toggleCollapsed()
    }

    private func chevronImage(collapsed: Bool) -> NSImage? {
        let name = collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Toggle hidden icons")
        image?.isTemplate = true
        return image
    }

    private func separatorImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { _ in
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 1, width: 2, height: 14),
                         xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
