import Foundation
import CryptoKit

/// Exact-duplicate detection: group by size, then by hash of the first 1 MB,
/// then confirm with a full-content SHA-256. Zero false positives.
enum DuplicateScanner {

    static func scan(roots: [URL], progress: @escaping (String) -> Void) -> [DuplicateGroup] {
        progress("Listing files…")
        var bySize: [Int64: [URL]] = [:]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isPackageKey]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true, values.isPackage != true,
                      let size = values.fileSize, size > 0 else { continue }
                bySize[Int64(size), default: []].append(url)
            }
        }

        let sizeGroups = bySize.filter { $0.value.count > 1 }
        var groups: [DuplicateGroup] = []
        var done = 0

        for (size, urls) in sizeGroups {
            done += 1
            progress("Comparing candidates… (\(done)/\(sizeGroups.count) groups)")

            // Pass 1: hash of first 1 MB
            var byPartial: [String: [URL]] = [:]
            for url in urls {
                guard let h = hash(url, limit: 1_048_576) else { continue }
                byPartial[h, default: []].append(url)
            }
            // Pass 2: full hash to confirm (skip for files fully covered by pass 1)
            for (partialHash, candidates) in byPartial where candidates.count > 1 {
                var byFull: [String: [URL]] = [:]
                for url in candidates {
                    let full = size <= 1_048_576 ? partialHash : (hash(url, limit: nil) ?? "")
                    guard !full.isEmpty else { continue }
                    byFull[full, default: []].append(url)
                }
                for (fullHash, dupes) in byFull where dupes.count > 1 {
                    let sorted = dupes.sorted { $0.path < $1.path }
                    let files = sorted.enumerated().map { idx, url in
                        RemovalItem(id: url.path, url: url,
                                    label: url.deletingLastPathComponent().path
                                        .replacingOccurrences(of: FileUtils.home.path, with: "~"),
                                    size: size,
                                    selected: idx > 0) // keep the first, mark the rest
                    }
                    groups.append(DuplicateGroup(id: fullHash, files: files))
                }
            }
        }
        return groups.sorted { $0.wastedSize > $1.wastedSize }
    }

    private static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let chunkSize = min(remaining, 1_048_576)
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
