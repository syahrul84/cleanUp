import Foundation
import AppKit

/// Self-updater backed by GitHub Releases. Checks the latest release, and on
/// request downloads the zip asset, swaps the app bundle in place (old version
/// goes to the Trash), and relaunches.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release {
        let version: String   // "1.5"
        let notes: String
        let zipURL: URL
    }

    enum Phase: Equatable {
        case idle, checking, downloading, installing
        case failed(String)
        case upToDate
    }

    @Published var available: Release?
    @Published var phase: Phase = .idle

    private static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/syahrul84/cleanUp/releases/latest")!

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Check GitHub for a newer release. `manual` surfaces "up to date"/errors
    /// in the UI; the quiet launch check only surfaces an actual update.
    func check(manual: Bool = false) {
        guard phase != .checking, phase != .downloading, phase != .installing else { return }
        phase = .checking
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data, let release = Self.parse(data) else {
                    self.phase = manual
                        ? .failed(error?.localizedDescription ?? "Could not reach GitHub.")
                        : .idle
                    return
                }
                if Self.isNewer(release.version, than: self.currentVersion) {
                    self.available = release
                    self.phase = .idle
                } else {
                    self.available = nil
                    self.phase = manual ? .upToDate : .idle
                }
            }
        }.resume()
    }

    /// Download the update, replace this app bundle, and relaunch.
    func installUpdate() {
        guard let release = available, phase != .downloading, phase != .installing else { return }
        phase = .downloading
        URLSession.shared.downloadTask(with: release.zipURL) { tempZip, _, error in
            guard let tempZip else {
                DispatchQueue.main.async {
                    self.phase = .failed(error?.localizedDescription ?? "Download failed.")
                }
                return
            }
            do {
                try self.replaceAndRelaunch(zip: tempZip)
            } catch {
                DispatchQueue.main.async { self.phase = .failed(error.localizedDescription) }
            }
        }.resume()
    }

    // MARK: - Internals

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let urlString = zipAsset["browser_download_url"] as? String,
              let zipURL = URL(string: urlString) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", zipURL: zipURL)
    }

    /// Numeric semver-style comparison: "1.10" > "1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func replaceAndRelaunch(zip: URL) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("CleanUpUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zipCopy = workDir.appendingPathComponent("update.zip")
        try fm.copyItem(at: zip, to: zipCopy)

        // Unpack with ditto (preserves signatures and resource forks).
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", zipCopy.path, workDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw NSError(domain: "Updater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not unpack the update."])
        }
        guard let newApp = try fm.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "Updater", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The update did not contain an app."])
        }

        DispatchQueue.main.sync { self.phase = .installing }

        // Swap: current bundle goes to the Trash (recoverable), new one takes its place.
        let target = Bundle.main.bundleURL
        try fm.trashItem(at: target, resultingItemURL: nil)
        try fm.copyItem(at: newApp, to: target)

        // Relaunch the new version after this process exits.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"\(target.path)\""]
        try relaunch.run()

        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
