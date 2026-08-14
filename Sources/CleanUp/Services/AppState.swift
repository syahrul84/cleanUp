import Foundation
import SwiftUI

extension Notification.Name {
    static let runSmartScan = Notification.Name("runSmartScan")
}

/// Cross-scene state: lets the menu bar extra steer the main window.
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var smartScanRequest = 0
    @Published var openFeatureRequest: Feature?

    /// Ask the main window to switch to the given sidebar feature.
    func open(_ feature: Feature) {
        openFeatureRequest = feature
    }

    /// Switch the main window to Smart Scan and start a scan.
    func requestSmartScan() {
        smartScanRequest += 1
        // Give the window a moment to appear/switch tabs before the view listens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .runSmartScan, object: nil)
        }
    }
}

/// Free/total capacity of the boot volume, refreshed on demand.
final class DiskStatus: ObservableObject {
    @Published var free: Int64 = 0
    @Published var total: Int64 = 0

    init() { refresh() }

    func refresh() {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        total = Int64(values?.volumeTotalCapacity ?? 0)
    }

    var freeShort: String {
        ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }
}
