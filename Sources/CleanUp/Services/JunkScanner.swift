import Foundation

enum JunkScanner {

    /// Progress: the bar steps once per category; the status line names
    /// each folder as it's measured. The reporter rides in thread-local
    /// storage so every size lookup below can report without extra plumbing.
    static func scan(progress: ScanProgressReporter? = nil,
                     span: ClosedRange<Double> = 0...1) -> [JunkCategory] {
        let kinds = JunkCategoryKind.allCases
        let width = span.upperBound - span.lowerBound
        var result: [JunkCategory] = []
        for (index, kind) in kinds.enumerated() {
            let start = span.lowerBound + width * Double(index) / Double(kinds.count)
            progress?.report(start, "Checking \(kind.rawValue)…", force: true)
            Thread.current.threadDictionary[progressKey] =
                progress.map { MeasureContext(reporter: $0, fraction: start, category: kind.rawValue) }
            let items = items(for: kind)
            if !items.isEmpty { result.append(JunkCategory(kind: kind, items: items)) }
        }
        Thread.current.threadDictionary[progressKey] = nil
        progress?.report(span.upperBound, "Finishing up…", force: true)
        return result
    }

    private static let progressKey = "JunkScanner.progress"

    private final class MeasureContext {
        let reporter: ScanProgressReporter
        let fraction: Double
        let category: String
        init(reporter: ScanProgressReporter, fraction: Double, category: String) {
            self.reporter = reporter; self.fraction = fraction; self.category = category
        }
    }

    private static func items(for kind: JunkCategoryKind) -> [RemovalItem] {
        let home = FileUtils.home
        let lib = home.appendingPathComponent("Library")

        switch kind {
        case .userCaches:
            // Trash each cache subfolder, not ~/Library/Caches itself.
            return FileUtils.children(of: lib.appendingPathComponent("Caches"))
                .filter { $0.lastPathComponent != "com.apple.HomeKit" } // avoid pain points
                .map { item($0, label: $0.lastPathComponent, selected: kind.defaultSelected) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }

        case .logs:
            return FileUtils.children(of: lib.appendingPathComponent("Logs"))
                .map { item($0, label: $0.lastPathComponent) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }

        case .xcode:
            let dev = lib.appendingPathComponent("Developer")
            let candidates: [(URL, String)] = [
                (dev.appendingPathComponent("Xcode/DerivedData"), "DerivedData"),
                (dev.appendingPathComponent("Xcode/iOS DeviceSupport"), "iOS Device Support"),
                (dev.appendingPathComponent("Xcode/watchOS DeviceSupport"), "watchOS Device Support"),
                (dev.appendingPathComponent("Xcode/tvOS DeviceSupport"), "tvOS Device Support"),
                (dev.appendingPathComponent("Xcode/iOS Device Logs"), "iOS Device Logs"),
                (dev.appendingPathComponent("Xcode/UserData/Previews/Simulator Devices"), "SwiftUI Preview Caches"),
                (dev.appendingPathComponent("CoreSimulator/Caches"), "Simulator Caches"),
                (dev.appendingPathComponent("XCPGDevices"), "Playground Devices"),
                (dev.appendingPathComponent("XCTestDevices"), "Test Devices"),
                (lib.appendingPathComponent("Caches/com.apple.dt.Xcode"), "Xcode Cache"),
            ]
            var items = existingItems(candidates)
            // Archives hold the user's release builds and dSYMs — shown for
            // completeness, never pre-selected.
            let archives = dev.appendingPathComponent("Xcode/Archives")
            if FileUtils.exists(archives) {
                let entry = item(archives, label: "Archives (your release builds!)", selected: false)
                if entry.size > 0 { items.append(entry) }
            }
            return items.sorted { $0.size > $1.size }

        case .devCaches:
            let candidates: [(URL, String)] = [
                (home.appendingPathComponent(".npm/_cacache"), "npm cache"),
                (home.appendingPathComponent(".cache"), "~/.cache"),
                (lib.appendingPathComponent("Caches/pip"), "pip cache"),
                (lib.appendingPathComponent("Caches/Homebrew"), "Homebrew cache"),
                (lib.appendingPathComponent("Caches/Yarn"), "Yarn cache"),
                (home.appendingPathComponent(".gradle/caches"), "Gradle cache"),
                (lib.appendingPathComponent("Caches/CocoaPods"), "CocoaPods cache"),
                (lib.appendingPathComponent("Caches/org.swift.swiftpm"), "Swift Package cache"),
            ]
            return existingItems(candidates)

        case .browserCaches:
            let candidates: [(URL, String)] = [
                (lib.appendingPathComponent("Caches/Google/Chrome"), "Chrome cache"),
                (lib.appendingPathComponent("Caches/Firefox"), "Firefox cache"),
                (lib.appendingPathComponent("Caches/com.brave.Browser"), "Brave cache"),
                (lib.appendingPathComponent("Caches/Microsoft Edge"), "Edge cache"),
                (lib.appendingPathComponent("Caches/Arc"), "Arc cache"),
            ]
            return existingItems(candidates)

        case .iosBackups:
            let backups = lib.appendingPathComponent("Application Support/MobileSync/Backup")
            return FileUtils.children(of: backups)
                .map { item($0, label: "Backup \($0.lastPathComponent.prefix(8))…", selected: false) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }

        case .trash:
            return FileUtils.children(of: home.appendingPathComponent(".Trash"), includeHidden: true)
                .map { item($0, label: $0.lastPathComponent, selected: false) }
                .sorted { $0.size > $1.size }
        }
    }

    private static func existingItems(_ candidates: [(URL, String)]) -> [RemovalItem] {
        candidates
            .filter { FileUtils.exists($0.0) }
            .map { item($0.0, label: $0.1) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    private static func item(_ url: URL, label: String, selected: Bool = true) -> RemovalItem {
        if let context = Thread.current.threadDictionary[progressKey] as? MeasureContext {
            context.reporter.report(context.fraction, "\(context.category): measuring \(label)…")
        }
        let context = Thread.current.threadDictionary[progressKey] as? MeasureContext
        let size = FileUtils.size(of: url) { bytes, files in
            context?.reporter.report(context!.fraction,
                "\(context!.category): measuring \(label) — \(Format.bytes(bytes)) so far (\(files.formatted()) files)")
        }
        return RemovalItem(id: url.path, url: url, label: label, size: size, selected: selected)
    }
}
