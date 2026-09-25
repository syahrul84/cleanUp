import Foundation

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
    static func trash(_ urls: [URL]) -> (trashed: Int, errors: [String]) {
        var trashed = 0
        var errors: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed += 1
            } catch {
                errors.append("\(url.path): \(error.localizedDescription)")
            }
        }
        return (trashed, errors)
    }
}
