import Foundation
import CryptoKit

/// Exact-duplicate detection: group by size, then by hash of the first 1 MB,
/// then confirm with a full-content SHA-256. Zero false positives.
enum DuplicateScanner {

    /// Progress: listing files fills the first 40% of the bar, comparing
    /// candidates (weighted by how many files each size group holds) the rest.
    static func scan(roots: [URL], progress: ScanProgressReporter? = nil) -> [DuplicateGroup] {
        var bySize: [Int64: [URL]] = [:]
        FileWalker.walk(roots: roots, keys: [.fileSizeKey], reporter: progress,
                        span: 0...0.4, verb: "Listing") { url, values in
            guard let size = values.fileSize, size > 0 else { return }
            bySize[Int64(size), default: []].append(url)
        }

        let sizeGroups = bySize.filter { $0.value.count > 1 }
        let totalCandidates = max(sizeGroups.values.reduce(0) { $0 + $1.count }, 1)
        var groups: [DuplicateGroup] = []
        var compared = 0

        for (size, urls) in sizeGroups {
            progress?.report(0.4 + 0.6 * Double(compared) / Double(totalCandidates),
                             "Comparing \(compared.formatted()) of \(totalCandidates.formatted()) same-size files — \(urls.first?.lastPathComponent ?? "")")
            compared += urls.count

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
        progress?.report(1, "Finishing up…", force: true)
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
