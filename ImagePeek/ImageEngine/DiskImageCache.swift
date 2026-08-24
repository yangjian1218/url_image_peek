import CryptoKit
import Foundation

protocol CacheClock: Sendable {
    func currentDate() -> Date
}

struct SystemCacheClock: CacheClock {
    func currentDate() -> Date {
        Date()
    }
}

struct DiskCacheSummary: Equatable, Sendable {
    let entryCount: Int
    let byteCount: Int
}

actor DiskImageCache {
    private static let defaultMaximumBytes = 1_073_741_824
    private static let defaultMaximumAge: TimeInterval = 30 * 24 * 60 * 60

    private let directory: URL
    private let maximumBytes: Int
    private let maximumAge: TimeInterval
    private let clock: any CacheClock

    init(
        directory: URL,
        maximumBytes: Int = DiskImageCache.defaultMaximumBytes,
        maximumAge: TimeInterval = DiskImageCache.defaultMaximumAge,
        clock: any CacheClock = SystemCacheClock()
    ) {
        precondition(maximumBytes > 0, "Disk image cache byte limit must be positive.")
        precondition(maximumAge > 0, "Disk image cache age limit must be positive.")
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.maximumAge = maximumAge
        self.clock = clock
    }

    func value(for key: ImageCacheKey) -> Data? {
        guard prepareDirectory() else { return nil }

        var manifest = loadManifest()
        let currentDate = clock.currentDate()
        removeExpiredEntries(from: &manifest, currentDate: currentDate)
        let identifier = cacheIdentifier(for: key)

        guard var entry = manifest.entries[identifier] else {
            saveManifest(manifest)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL(for: entry.fileName)) else {
            manifest.entries.removeValue(forKey: identifier)
            saveManifest(manifest)
            return nil
        }

        entry.lastAccessed = currentDate.timeIntervalSince1970
        manifest.entries[identifier] = entry
        saveManifest(manifest)
        return data
    }

    func insert(_ data: Data, for key: ImageCacheKey) {
        guard prepareDirectory() else { return }

        var manifest = loadManifest()
        let currentDate = clock.currentDate()
        removeExpiredEntries(from: &manifest, currentDate: currentDate)
        let identifier = cacheIdentifier(for: key)
        let fileName = "\(identifier).image"

        guard (try? data.write(to: fileURL(for: fileName), options: .atomic)) != nil else {
            saveManifest(manifest)
            return
        }

        manifest.entries[identifier] = DiskCacheEntry(
            fileName: fileName,
            byteCount: data.count,
            lastAccessed: currentDate.timeIntervalSince1970
        )
        enforceByteLimit(on: &manifest)
        saveManifest(manifest)
    }

    func summary() -> DiskCacheSummary? {
        guard prepareDirectory() else { return nil }
        var manifest = loadManifest()
        removeExpiredEntries(from: &manifest, currentDate: clock.currentDate())
        saveManifest(manifest)
        return DiskCacheSummary(
            entryCount: manifest.entries.count,
            byteCount: manifest.entries.values.reduce(0) { $0 + $1.byteCount }
        )
    }

    func clear() -> Bool {
        guard prepareDirectory() else { return false }
        let manifest = loadManifest()
        for entry in manifest.entries.values {
            removeFile(named: entry.fileName)
        }
        saveManifest(DiskCacheManifest(entries: [:]))
        return true
    }

    private func prepareDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private func loadManifest() -> DiskCacheManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(DiskCacheManifest.self, from: data) else {
            return DiskCacheManifest(entries: [:])
        }
        return manifest
    }

    private func saveManifest(_ manifest: DiskCacheManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func removeExpiredEntries(from manifest: inout DiskCacheManifest, currentDate: Date) {
        for (identifier, entry) in manifest.entries where currentDate.timeIntervalSince1970 - entry.lastAccessed > maximumAge {
            removeFile(named: entry.fileName)
            manifest.entries.removeValue(forKey: identifier)
        }
    }

    private func enforceByteLimit(on manifest: inout DiskCacheManifest) {
        var totalBytes = manifest.entries.values.reduce(0) { $0 + $1.byteCount }
        let entriesByOldestAccess = manifest.entries.sorted {
            $0.value.lastAccessed == $1.value.lastAccessed
                ? $0.key < $1.key
                : $0.value.lastAccessed < $1.value.lastAccessed
        }

        for (identifier, entry) in entriesByOldestAccess where totalBytes > maximumBytes {
            removeFile(named: entry.fileName)
            manifest.entries.removeValue(forKey: identifier)
            totalBytes -= entry.byteCount
        }
    }

    private func removeFile(named fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
    }

    private func cacheIdentifier(for key: ImageCacheKey) -> String {
        let source = "\(key.originalURLString)|\(key.optimizationRuleVersion)"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var manifestURL: URL {
        directory.appendingPathComponent("manifest.json")
    }

    private func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }
}

private struct DiskCacheManifest: Codable {
    var entries: [String: DiskCacheEntry]
}

private struct DiskCacheEntry: Codable {
    let fileName: String
    let byteCount: Int
    var lastAccessed: TimeInterval
}
