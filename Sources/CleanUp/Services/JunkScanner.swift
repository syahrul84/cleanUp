import Foundation

enum JunkScanner {

    static func scan() -> [JunkCategory] {
        JunkCategoryKind.allCases.compactMap { kind in
            let items = items(for: kind)
            return items.isEmpty ? nil : JunkCategory(kind: kind, items: items)
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
                (dev.appendingPathComponent("CoreSimulator/Caches"), "Simulator Caches"),
                (lib.appendingPathComponent("Caches/com.apple.dt.Xcode"), "Xcode Cache"),
            ]
            return existingItems(candidates)

        case .devCaches:
            let candidates: [(URL, String)] = [
                (home.appendingPathComponent(".npm/_cacache"), "npm cache"),
                (home.appendingPathComponent(".cache"), "~/.cache"),
                (lib.appendingPathComponent("Caches/pip"), "pip cache"),
                (lib.appendingPathComponent("Caches/Homebrew"), "Homebrew cache"),
                (lib.appendingPathComponent("Caches/Yarn"), "Yarn cache"),
                (home.appendingPathComponent(".gradle/caches"), "Gradle cache"),
                (lib.appendingPathComponent("Caches/CocoaPods"), "CocoaPods cache"),
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
        RemovalItem(id: url.path, url: url, label: label,
                    size: FileUtils.size(of: url), selected: selected)
    }
}
