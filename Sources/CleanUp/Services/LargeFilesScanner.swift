import Foundation

enum LargeFilesScanner {

    /// Files >= minSize under the given roots, largest first, capped at `limit`.
    static func scan(roots: [URL], minSize: Int64 = 50 * 1_048_576, limit: Int = 300,
                     progress: ScanProgressReporter? = nil) -> [LargeFile] {
        var results: [LargeFile] = []
        FileWalker.walk(roots: roots, keys: [.fileSizeKey, .contentAccessDateKey],
                        reporter: progress, verb: "Scanning") { url, values in
            guard let size = values.fileSize, Int64(size) >= minSize else { return }
            results.append(LargeFile(id: url.path, url: url, size: Int64(size),
                                     lastAccess: values.contentAccessDate))
        }
        return Array(results.sorted { $0.size > $1.size }.prefix(limit))
    }
}
