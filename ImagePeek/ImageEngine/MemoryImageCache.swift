import Foundation

struct ImageCacheKey: Hashable, Sendable {
    let originalURLString: String
    let optimizationRuleVersion: String

    init(originalURL: URL, optimizationRuleVersion: String) {
        self.originalURLString = originalURL.absoluteString
        self.optimizationRuleVersion = optimizationRuleVersion
    }
}

actor MemoryImageCache {
    private let capacity: Int
    private var values: [ImageCacheKey: Data] = [:]
    private var recency: [ImageCacheKey] = []

    init(capacity: Int = 200) {
        precondition(capacity > 0, "Memory image cache capacity must be positive.")
        self.capacity = capacity
    }

    var count: Int {
        values.count
    }

    func value(for key: ImageCacheKey) -> Data? {
        guard let value = values[key] else { return nil }
        markAsMostRecentlyUsed(key)
        return value
    }

    func insert(_ value: Data, for key: ImageCacheKey) {
        values[key] = value
        markAsMostRecentlyUsed(key)

        while values.count > capacity, let leastRecentlyUsedKey = recency.first {
            recency.removeFirst()
            values.removeValue(forKey: leastRecentlyUsedKey)
        }
    }

    func removeAll() {
        values.removeAll()
        recency.removeAll()
    }

    private func markAsMostRecentlyUsed(_ key: ImageCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
