import Foundation
import AppKit

// MARK: - Installed application

struct AppInfo: Identifiable, Hashable {
    let id: String            // bundle path
    let name: String
    let bundleID: String?
    let url: URL
    var size: Int64?          // computed lazily in background
    let icon: NSImage

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - A file/folder candidate for removal

struct RemovalItem: Identifiable, Hashable {
    let id: String            // path
    let url: URL
    let label: String         // human-readable location description
    var size: Int64
    var selected: Bool = true
}

// MARK: - Junk categories

enum JunkCategoryKind: String, CaseIterable, Identifiable {
    case userCaches = "User Caches"
    case logs = "Logs"
    case xcode = "Xcode & Simulators"
    case devCaches = "Developer Caches"
    case browserCaches = "Browser Caches"
    case iosBackups = "Old iOS Backups"
    case trash = "Trash"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .logs: return "doc.text"
        case .xcode: return "hammer"
        case .devCaches: return "terminal"
        case .browserCaches: return "globe"
        case .iosBackups: return "iphone"
        case .trash: return "trash"
        }
    }

    var explanation: String {
        switch self {
        case .userCaches: return "App caches in ~/Library/Caches. Apps rebuild these as needed."
        case .logs: return "Old log files in ~/Library/Logs."
        case .xcode: return "DerivedData, module caches and simulator caches. Xcode regenerates them."
        case .devCaches: return "npm, pip, Homebrew and similar package-manager caches."
        case .browserCaches: return "Chrome, Firefox and other browser caches. You stay logged in."
        case .iosBackups: return "Local iPhone/iPad backups. Only remove if backed up elsewhere!"
        case .trash: return "Files already in your Trash."
        }
    }

    /// Categories that are risky enough to be deselected by default.
    var defaultSelected: Bool {
        switch self {
        case .iosBackups, .trash: return false
        default: return true
        }
    }
}

struct JunkCategory: Identifiable {
    let kind: JunkCategoryKind
    var items: [RemovalItem]
    var id: String { kind.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
}

// MARK: - Duplicates

struct DuplicateGroup: Identifiable {
    let id: String            // full-content hash
    var files: [RemovalItem]  // 2+ identical files; selection marks files to REMOVE
    var fileSize: Int64 { files.first?.size ?? 0 }
    var wastedSize: Int64 { Int64(max(0, files.count - 1)) * fileSize }
}

// MARK: - Large & old files

struct LargeFile: Identifiable, Hashable {
    let id: String            // path
    let url: URL
    let size: Int64
    let lastAccess: Date?
    var selected: Bool = false
}

// MARK: - Shared helpers

enum Format {
    static func bytes(_ n: Int64?) -> String {
        guard let n else { return "…" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
