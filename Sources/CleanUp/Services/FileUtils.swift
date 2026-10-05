import Foundation
import AppKit

enum FileUtils {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Recursive size of a file or directory, in bytes. Cheap resource-key based walk.
    /// `onProgress` (bytes so far, files so far) fires every 500 files, so
    /// callers can show that a long measurement is still moving.
    static func size(of url: URL, onProgress: ((Int64, Int) -> Void)? = nil) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                             options: [], errorHandler: { _, _ in true }) else { return 0 }
        var files = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            files += 1
            if files % 500 == 0 { onProgress?(total, files) }
        }
        return total
    }

    /// Immediate children of a directory (non-hidden by default), or [] on failure.
    static func children(of url: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: options)) ?? []
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Move items to Trash. Returns (trashedCount, errors). Never permanently deletes.
    @discardableResult
    /// Call off the main thread. Items owned by the system (App Store apps
    /// like GarageBand are owned by root) can't be moved by CleanUp itself;
    /// those are handed to Finder, which asks for an admin password the same
    /// way dragging them to the Trash does.
    static func trash(_ urls: [URL]) -> (trashed: Int, errors: [String]) {
        var trashed = 0
        var errors: [String] = []
        var needsAuth: [URL] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed += 1
            } catch {
                needsAuth.append(url)
            }
        }
        if !needsAuth.isEmpty {
            // Items owned by the system (App Store apps are owned by root)
            // need an admin. Finder's recycle API refuses them without even
            // prompting, so ask for the password with the standard macOS
            // dialog and move them into the user's Trash ourselves.
            let trashDir = home.appendingPathComponent(".Trash")
            var moves: [(URL, URL)] = []
            for url in needsAuth {
                var dest = trashDir.appendingPathComponent(url.lastPathComponent)
                var n = 2
                while FileManager.default.fileExists(atPath: dest.path) {
                    let base = url.deletingPathExtension().lastPathComponent
                    let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
                    dest = trashDir.appendingPathComponent("\(base) \(n)\(ext)")
                    n += 1
                }
                moves.append((url, dest))
            }
            func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let command = moves.map { "mv \(quoted($0.0.path)) \(quoted($0.1.path))" }.joined(separator: "; ")
            let names = needsAuth.map(\.lastPathComponent).joined(separator: ", ")
            let script = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges with prompt \"CleanUp needs your password to move \(names.replacingOccurrences(of: "\"", with: "")) to the Trash.\""
            var scriptError: NSDictionary?
            DispatchQueue.main.sync {
                _ = NSAppleScript(source: script)?.executeAndReturnError(&scriptError)
            }
            for (src, _) in moves {
                if FileManager.default.fileExists(atPath: src.path) {
                    let reason = (scriptError?[NSAppleScript.errorNumber] as? Int) == -128
                        ? "cancelled" : (scriptError?[NSAppleScript.errorMessage] as? String ?? "not moved")
                    errors.append("\(src.lastPathComponent): \(reason)")
                } else {
                    trashed += 1
                }
            }
        }
        return (trashed, errors)
    }
}
