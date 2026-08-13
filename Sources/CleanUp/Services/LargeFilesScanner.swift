import Foundation

enum LargeFilesScanner {

    /// Files >= minSize under the given roots, largest first, capped at `limit`.
    static func scan(roots: [URL], minSize: Int64 = 50 * 1_048_576, limit: Int = 300) -> [LargeFile] {
        var results: [LargeFile] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey,
                                         .contentAccessDateKey, .isPackageKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let size = values.fileSize, Int64(size) >= minSize else { continue }
                results.append(LargeFile(id: url.path, url: url, size: Int64(size),
                                         lastAccess: values.contentAccessDate))
            }
        }
        return Array(results.sorted { $0.size > $1.size }.prefix(limit))
    }
}
