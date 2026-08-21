import Foundation

struct RemoteImageData: Equatable, Sendable {
    let url: URL
    let data: Data
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
    private let fetcher: any RemoteDataFetching
    private var requestGeneration = 0
    private var currentTask: Task<Data, Error>?

    init(fetcher: any RemoteDataFetching = URLSessionDataFetcher()) {
        self.fetcher = fetcher
    }

    func loadData(from url: URL) async throws -> RemoteImageData? {
        requestGeneration &+= 1
        let generation = requestGeneration
        currentTask?.cancel()

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
            return RemoteImageData(url: url, data: data)
        } catch is CancellationError {
            return nil
        }
    }

    func cancelCurrentLoad() {
        requestGeneration &+= 1
        currentTask?.cancel()
        currentTask = nil
    }
}
