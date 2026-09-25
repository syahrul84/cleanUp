import AppKit

/// Icons for not-yet-installed casks, fetched from each app's own homepage
/// (apple-touch-icon, then favicon) — vendor-direct, no aggregator service.
/// Cached on disk permanently after the first fetch; a zero-byte marker
/// negative-caches sites that have no usable icon.
final class CaskIconStore {
    static let shared = CaskIconStore()

    private let memory = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "cask-icons", qos: .utility, attributes: .concurrent)

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("CleanUp/cask-icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func icon(for token: String, homepage: String,
              completion: @escaping (NSImage?) -> Void) {
        if let cached = memory.object(forKey: token as NSString) {
            completion(cached)
            return
        }
        queue.async { [self] in
            let file = cacheDir.appendingPathComponent("\(token).png")
            if let data = try? Data(contentsOf: file) {
                // Zero-byte marker = known to have no icon; don't refetch.
                let image = data.isEmpty ? nil : NSImage(data: data)
                if let image { memory.setObject(image, forKey: token as NSString) }
                DispatchQueue.main.async { completion(image) }
                return
            }
            guard let host = URL(string: homepage)?.host else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            for path in ["apple-touch-icon.png", "favicon.ico"] {
                if let data = fetch("https://\(host)/\(path)"),
                   let image = NSImage(data: data), image.size.width > 0 {
                    try? data.write(to: file)
                    memory.setObject(image, forKey: token as NSString)
                    DispatchQueue.main.async { completion(image) }
                    return
                }
            }
            try? Data().write(to: file) // negative-cache
            DispatchQueue.main.async { completion(nil) }
        }
    }

    private func fetch(_ urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, !data.isEmpty {
                result = data
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }
}
