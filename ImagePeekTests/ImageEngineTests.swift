import XCTest
@testable import ImagePeek

final class ImageEngineTests: XCTestCase {
    func testResolverAcceptsRemoteHTTPAndHTTPSURLs() {
        let resolver = ImageSourceResolver()

        XCTAssertEqual(
            resolver.resolve(" https://example.com/image.jpg "),
            .remote(URL(string: "https://example.com/image.jpg")!)
        )
        XCTAssertEqual(
            resolver.resolve("http://example.com/image.jpg"),
            .remote(URL(string: "http://example.com/image.jpg")!)
        )
    }

    func testResolverAcceptsAbsoluteTildeAndFileURLsAsLocalSources() {
        let resolver = ImageSourceResolver()
        let homeImage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/image.png")

        XCTAssertEqual(resolver.resolve(homeImage.path), .local(homeImage))
        XCTAssertEqual(resolver.resolve("~/Pictures/image.png"), .local(homeImage))
        XCTAssertEqual(
            resolver.resolve("file:///tmp/image.png"),
            .local(URL(fileURLWithPath: "/tmp/image.png"))
        )
    }

    func testResolverRejectsUnsupportedOrMalformedText() {
        let resolver = ImageSourceResolver()

        XCTAssertNil(resolver.resolve("ftp://example.com/image.jpg"))
        XCTAssertNil(resolver.resolve("example.com/image.jpg"))
        XCTAssertNil(resolver.resolve("   "))
    }

    func testAliyunRuleAddsVerifiedResizeProcessToUnsignedURL() {
        let url = URL(string: "https://bucket.oss-cn-hangzhou.aliyuncs.com/image.jpg")!
        let optimized = CDNOptimizer().optimizedURL(for: url)

        XCTAssertEqual(optimized.host, url.host)
        XCTAssertEqual(
            URLComponents(url: optimized, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "x-oss-process", value: "image/resize,l_900")]
        )
    }

    func testAliyunRulePreservesExistingQueryAndSkipsProcessedOrSignedURLs() {
        let optimizer = CDNOptimizer()
        let existingQuery = URL(string: "https://a.aliyuncs.com/i.jpg?foo=bar")!
        let processed = URL(string: "https://a.aliyuncs.com/i.jpg?x-oss-process=image/resize,l_100")!
        let signed = URL(string: "https://a.aliyuncs.com/i.jpg?Signature=abc")!

        let optimizedExisting = optimizer.optimizedURL(for: existingQuery)
        XCTAssertEqual(
            URLComponents(url: optimizedExisting, resolvingAgainstBaseURL: false)?.queryItems,
            [
                URLQueryItem(name: "foo", value: "bar"),
                URLQueryItem(name: "x-oss-process", value: "image/resize,l_900"),
            ]
        )
        XCTAssertEqual(optimizer.optimizedURL(for: processed), processed)
        XCTAssertEqual(optimizer.optimizedURL(for: signed), signed)
    }

    func testOptimizerLeavesUnknownCDNAndLocalURLsUntouched() {
        let optimizer = CDNOptimizer()
        let unknown = URL(string: "https://img.kwcdn.com/image.jpg")!
        let local = URL(fileURLWithPath: "/tmp/image.jpg")

        XCTAssertEqual(optimizer.optimizedURL(for: unknown), unknown)
        XCTAssertEqual(optimizer.optimizedURL(for: local), local)
    }

    func testRemoteLoaderReturnsFetchedDataForCurrentRequest() async throws {
        let url = URL(string: "https://example.com/image.jpg")!
        let data = Data([0x01, 0x02])
        let loader = RemoteImageLoader(fetcher: ImmediateDataFetcher(values: [url: data]))

        let result = try await loader.loadData(from: url)

        XCTAssertEqual(result?.url, url)
        XCTAssertEqual(result?.data, data)
    }

    func testNewerRemoteRequestSupersedesEarlierCompletion() async throws {
        let slowURL = URL(string: "https://example.com/slow.jpg")!
        let fastURL = URL(string: "https://example.com/fast.jpg")!
        let fetcher = ControlledDataFetcher(
            slowURL: slowURL,
            slowData: Data([0x01]),
            fastURL: fastURL,
            fastData: Data([0x02])
        )
        let loader = RemoteImageLoader(fetcher: fetcher)

        let olderRequest = Task { try await loader.loadData(from: slowURL) }
        await fetcher.waitUntilSlowRequestStarts()
        let latestResult = try await loader.loadData(from: fastURL)
        await fetcher.completeSlowRequest()
        let olderResult = try await olderRequest.value

        XCTAssertEqual(latestResult?.url, fastURL)
        XCTAssertEqual(latestResult?.data, Data([0x02]))
        XCTAssertNil(olderResult)
    }

    func testCancellingCurrentRemoteRequestSuppressesLateResult() async throws {
        let slowURL = URL(string: "https://example.com/slow.jpg")!
        let fetcher = ControlledDataFetcher(
            slowURL: slowURL,
            slowData: Data([0x01]),
            fastURL: URL(string: "https://example.com/fast.jpg")!,
            fastData: Data([0x02])
        )
        let loader = RemoteImageLoader(fetcher: fetcher)

        let request = Task { try await loader.loadData(from: slowURL) }
        await fetcher.waitUntilSlowRequestStarts()
        await loader.cancelCurrentLoad()
        await fetcher.completeSlowRequest()

        let result = try await request.value
        XCTAssertNil(result)
    }

    func testMemoryCacheReturnsStoredValue() async {
        let cache = MemoryImageCache(capacity: 2)
        let key = ImageCacheKey(
            originalURL: URL(string: "https://example.com/image.jpg")!,
            optimizationRuleVersion: "v1"
        )
        let data = Data([0x01, 0x02])

        await cache.insert(data, for: key)

        let cachedValue = await cache.value(for: key)
        XCTAssertEqual(cachedValue, data)
    }

    func testMemoryCacheEvictsLeastRecentlyUsedEntryWhenCapacityExceeded() async {
        let cache = MemoryImageCache(capacity: 2)
        let first = ImageCacheKey(originalURL: URL(string: "https://example.com/1.jpg")!, optimizationRuleVersion: "v1")
        let second = ImageCacheKey(originalURL: URL(string: "https://example.com/2.jpg")!, optimizationRuleVersion: "v1")
        let third = ImageCacheKey(originalURL: URL(string: "https://example.com/3.jpg")!, optimizationRuleVersion: "v1")

        await cache.insert(Data([0x01]), for: first)
        await cache.insert(Data([0x02]), for: second)
        _ = await cache.value(for: first)
        await cache.insert(Data([0x03]), for: third)

        let firstValue = await cache.value(for: first)
        let secondValue = await cache.value(for: second)
        let thirdValue = await cache.value(for: third)
        XCTAssertEqual(firstValue, Data([0x01]))
        XCTAssertNil(secondValue)
        XCTAssertEqual(thirdValue, Data([0x03]))
    }

    func testMemoryCacheReplacesExistingValueWithoutGrowing() async {
        let cache = MemoryImageCache(capacity: 2)
        let key = ImageCacheKey(
            originalURL: URL(string: "https://example.com/image.jpg")!,
            optimizationRuleVersion: "v1"
        )

        await cache.insert(Data([0x01]), for: key)
        await cache.insert(Data([0x02]), for: key)

        let count = await cache.count
        let cachedValue = await cache.value(for: key)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cachedValue, Data([0x02]))
    }

    func testMemoryCacheSeparatesOptimizationRuleVersions() async {
        let cache = MemoryImageCache(capacity: 2)
        let url = URL(string: "https://example.com/image.jpg")!
        let oldRule = ImageCacheKey(originalURL: url, optimizationRuleVersion: "v1")
        let newRule = ImageCacheKey(originalURL: url, optimizationRuleVersion: "v2")

        await cache.insert(Data([0x01]), for: oldRule)
        await cache.insert(Data([0x02]), for: newRule)

        let oldValue = await cache.value(for: oldRule)
        let newValue = await cache.value(for: newRule)
        XCTAssertEqual(oldValue, Data([0x01]))
        XCTAssertEqual(newValue, Data([0x02]))
    }

    func testDiskCacheReadsStoredDataAfterCacheIsRecreated() async {
        let directory = makeTemporaryCacheDirectory()
        let key = ImageCacheKey(
            originalURL: URL(string: "https://example.com/image.jpg")!,
            optimizationRuleVersion: "v1"
        )
        let data = Data([0x01, 0x02])

        let writer = DiskImageCache(directory: directory)
        await writer.insert(data, for: key)

        let reader = DiskImageCache(directory: directory)
        let cachedValue = await reader.value(for: key)
        XCTAssertEqual(cachedValue, data)
    }

    func testDiskCacheRemovesEntryUnusedForMoreThanThirtyDays() async {
        let directory = makeTemporaryCacheDirectory()
        let key = ImageCacheKey(
            originalURL: URL(string: "https://example.com/old.jpg")!,
            optimizationRuleVersion: "v1"
        )
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        let expirationInterval: TimeInterval = 30 * 24 * 60 * 60

        let writer = DiskImageCache(directory: directory, clock: FixedCacheClock(now: oldDate))
        await writer.insert(Data([0x01]), for: key)

        let reader = DiskImageCache(
            directory: directory,
            clock: FixedCacheClock(now: oldDate.addingTimeInterval(expirationInterval + 1))
        )
        let cachedValue = await reader.value(for: key)
        XCTAssertNil(cachedValue)
    }

    func testDiskCacheEvictsLeastRecentlyUsedEntryWhenByteLimitIsExceeded() async {
        let directory = makeTemporaryCacheDirectory()
        let first = ImageCacheKey(originalURL: URL(string: "https://example.com/1.jpg")!, optimizationRuleVersion: "v1")
        let second = ImageCacheKey(originalURL: URL(string: "https://example.com/2.jpg")!, optimizationRuleVersion: "v1")
        let third = ImageCacheKey(originalURL: URL(string: "https://example.com/3.jpg")!, optimizationRuleVersion: "v1")
        let initialDate = Date(timeIntervalSince1970: 1_000_000)
        let sixBytes = Data(repeating: 0x01, count: 6)

        let firstWriter = DiskImageCache(directory: directory, maximumBytes: 12, clock: FixedCacheClock(now: initialDate))
        await firstWriter.insert(sixBytes, for: first)
        let secondWriter = DiskImageCache(directory: directory, maximumBytes: 12, clock: FixedCacheClock(now: initialDate.addingTimeInterval(1)))
        await secondWriter.insert(sixBytes, for: second)
        let firstReader = DiskImageCache(directory: directory, maximumBytes: 12, clock: FixedCacheClock(now: initialDate.addingTimeInterval(2)))
        _ = await firstReader.value(for: first)

        let thirdWriter = DiskImageCache(directory: directory, maximumBytes: 12, clock: FixedCacheClock(now: initialDate.addingTimeInterval(3)))
        await thirdWriter.insert(sixBytes, for: third)
        let reader = DiskImageCache(directory: directory, maximumBytes: 12, clock: FixedCacheClock(now: initialDate.addingTimeInterval(4)))

        let firstValue = await reader.value(for: first)
        let secondValue = await reader.value(for: second)
        let thirdValue = await reader.value(for: third)
        XCTAssertEqual(firstValue, sixBytes)
        XCTAssertNil(secondValue)
        XCTAssertEqual(thirdValue, sixBytes)
    }
}

private struct ImmediateDataFetcher: RemoteDataFetching {
    let values: [URL: Data]

    func data(for url: URL) async throws -> Data {
        guard let data = values[url] else { throw URLError(.badURL) }
        return data
    }
}

private actor ControlledDataFetcher: RemoteDataFetching {
    private let slowURL: URL
    private let slowData: Data
    private let fastURL: URL
    private let fastData: Data
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var slowCompletion: CheckedContinuation<Data, Error>?

    init(slowURL: URL, slowData: Data, fastURL: URL, fastData: Data) {
        self.slowURL = slowURL
        self.slowData = slowData
        self.fastURL = fastURL
        self.fastData = fastData
    }

    func data(for url: URL) async throws -> Data {
        if url == fastURL { return fastData }
        guard url == slowURL else { throw URLError(.badURL) }

        return try await withCheckedThrowingContinuation { continuation in
            slowCompletion = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilSlowRequestStarts() async {
        if slowCompletion != nil { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func completeSlowRequest() {
        slowCompletion?.resume(returning: slowData)
        slowCompletion = nil
    }
}

private struct FixedCacheClock: CacheClock {
    let now: Date

    func currentDate() -> Date {
        now
    }
}

private func makeTemporaryCacheDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImagePeekTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
