import Foundation

/// Throttled progress callback for scanners: a 0…1 fraction plus a status
/// line, delivered on the main thread at most ~12 times a second. Updates
/// that arrive inside the throttle window aren't dropped — the latest one is
/// delivered when the window ends, so the screen never shows a stale step
/// while a slow operation runs.
final class ScanProgressReporter {
    private let handler: (Double, String) -> Void
    private let interval: TimeInterval = 0.08
    private let lock = NSLock()
    private var last = Date.distantPast
    private var pending: (Double, String)?
    private var flushScheduled = false

    init(_ handler: @escaping (Double, String) -> Void) {
        self.handler = handler
    }

    func report(_ fraction: Double, _ text: String, force: Bool = false) {
        let update = (min(max(fraction, 0), 1), text)
        lock.lock()
        let now = Date()
        let elapsed = now.timeIntervalSince(last)
        if force || elapsed >= interval {
            last = now
            pending = nil
            lock.unlock()
            deliver(update)
            return
        }
        pending = update
        let needsFlush = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsFlush {
            DispatchQueue.global().asyncAfter(deadline: .now() + (interval - elapsed)) { [self] in
                lock.lock()
                let latest = pending
                pending = nil
                flushScheduled = false
                if latest != nil { last = Date() }
                lock.unlock()
                if let latest { deliver(latest) }
            }
        }
    }

    private func deliver(_ update: (Double, String)) {
        DispatchQueue.main.async { self.handler(update.0, update.1) }
    }
}

/// Walks every file under a set of folders with measurable progress: the
/// top-level entries of each root are the work units, and a running file
/// count keeps the status line moving inside big folders.
enum FileWalker {
    static func walk(roots: [URL],
                     keys: Set<URLResourceKey>,
                     reporter: ScanProgressReporter?,
                     span: ClosedRange<Double> = 0...1,
                     verb: String = "Scanning",
                     visit: (URL, URLResourceValues) -> Void) {
        let fm = FileManager.default
        var units: [URL] = []
        for root in roots {
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles])) ?? []
            units += children.isEmpty ? [root] : children
        }
        let allKeys = keys.union([.isRegularFileKey, .isDirectoryKey, .isPackageKey])
        var filesSeen = 0
        let width = span.upperBound - span.lowerBound

        func progress(_ done: Int, _ name: String, force: Bool = false) {
            let fraction = span.lowerBound + width * Double(done) / Double(max(units.count, 1))
            reporter?.report(fraction, "\(verb) \(name) — \(filesSeen.formatted()) files checked",
                             force: force)
        }

        for (index, unit) in units.enumerated() {
            let name = unit.lastPathComponent
            progress(index, name, force: true)
            guard let values = try? unit.resourceValues(forKeys: allKeys) else { continue }
            if values.isRegularFile == true {
                filesSeen += 1
                visit(unit, values)
                continue
            }
            guard values.isDirectory == true, values.isPackage != true,
                  let enumerator = fm.enumerator(at: unit, includingPropertiesForKeys: Array(allKeys),
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                 errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard let v = try? url.resourceValues(forKeys: allKeys), v.isRegularFile == true else { continue }
                filesSeen += 1
                visit(url, v)
                if filesSeen % 200 == 0 { progress(index, name) }
            }
        }
        reporter?.report(span.upperBound, "\(verb) done — \(filesSeen.formatted()) files checked", force: true)
    }
}
