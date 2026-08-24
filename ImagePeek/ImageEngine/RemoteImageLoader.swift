import Foundation

struct RemoteImageData: Equatable, Sendable {
    let url: URL
    let data: Data
    let source: ImageLoadSource
}

enum ImageLoadSource: Equatable, Sendable {
    case network
    case diskCache
    case memoryCache
}

protocol RemoteDataFetching: Sendable {
    func data(for url: URL) async throws -> Data
}

enum RemoteImageLoaderError: Error, Equatable, Sendable {
    case httpStatus(Int)
}

struct URLSessionDataFetcher: RemoteDataFetching {
    func data(for url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw RemoteImageLoaderError.httpStatus(response.statusCode)
        }
        return data
    }
}

actor RemoteImageLoader {
    static let cacheRuleVersion = "cdn-v1"

    private let fetcher: any RemoteDataFetching
    private let memoryCache: MemoryImageCache
    private let diskCache: DiskImageCache
    private var requestGeneration = 0
    private var currentTask: Task<Data, Error>?

    init(
        fetcher: any RemoteDataFetching = URLSessionDataFetcher(),
        memoryCache: MemoryImageCache = MemoryImageCache(),
        diskCache: DiskImageCache? = nil
    ) {
        self.fetcher = fetcher
        self.memoryCache = memoryCache
        self.diskCache = diskCache ?? DiskImageCache(directory: Self.defaultCacheDirectory)
    }

    func loadData(from url: URL) async throws -> RemoteImageData? {
        requestGeneration &+= 1
        let generation = requestGeneration
        currentTask?.cancel()
        currentTask = nil

        let key = ImageCacheKey(originalURL: url, optimizationRuleVersion: Self.cacheRuleVersion)
        if let data = await memoryCache.value(for: key) {
            return generation == requestGeneration
                ? RemoteImageData(url: url, data: data, source: .memoryCache)
                : nil
        }

        if let data = await diskCache.value(for: key) {
            guard generation == requestGeneration else { return nil }
            await memoryCache.insert(data, for: key)
            return RemoteImageData(url: url, data: data, source: .diskCache)
        }

        let fetcher = self.fetcher
        let task = Task.detached(priority: nil) {
            try await fetcher.data(for: url)
        }
        currentTask = task
        defer {
            if generation == requestGeneration {
                currentTask = nil
            }
        }

        do {
            let data = try await task.value
            guard generation == requestGeneration else { return nil }
            await memoryCache.insert(data, for: key)
            let diskCache = self.diskCache
            Task {
                await diskCache.insert(data, for: key)
            }
            return RemoteImageData(url: url, data: data, source: .network)
        } catch is CancellationError {
            return nil
        }
    }

    func cancelCurrentLoad() {
        requestGeneration &+= 1
        currentTask?.cancel()
        currentTask = nil
    }

    func cacheSummary() async -> DiskCacheSummary? {
        await diskCache.summary()
    }

    func clearCache() async -> Bool {
        await memoryCache.removeAll()
        return await diskCache.clear()
    }

    private static var defaultCacheDirectory: URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cachesDirectory.appendingPathComponent("ImagePeek/ImageCache", isDirectory: true)
    }
}
