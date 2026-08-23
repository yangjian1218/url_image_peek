import Foundation

/// Namespace for image-source resolution, loading, optimization, and caching
/// components added in later Phase 1 iterations.
enum ImageEngine {}

enum PreviewRequest: Equatable {
    case remote(URL)
    case local(URL)
}

enum PreviewRuntimeDecision: Equatable {
    case hide
    case load(PreviewRequest, CellContext)
}

struct PreviewPipeline {
    private let resolver: ImageSourceResolver
    private let optimizer: CDNOptimizer

    init(resolver: ImageSourceResolver = ImageSourceResolver(), optimizer: CDNOptimizer = CDNOptimizer()) {
        self.resolver = resolver
        self.optimizer = optimizer
    }

    func request(for context: CellContext) -> PreviewRequest? {
        switch resolver.resolve(context.text) {
        case let .remote(url): return .remote(optimizer.optimizedURL(for: url))
        case let .local(url): return .local(url)
        case nil: return nil
        }
    }
}

struct PreviewRuntimeCoordinator {
    private let pipeline: PreviewPipeline
    private let imageColumnFilter: ImageColumnFilter

    init(
        pipeline: PreviewPipeline = PreviewPipeline(),
        imageColumnFilter: ImageColumnFilter = .all
    ) {
        self.pipeline = pipeline
        self.imageColumnFilter = imageColumnFilter
    }

    func decision(for context: CellContext?) -> PreviewRuntimeDecision {
        guard let context,
              imageColumnFilter.includes(column: context.column),
              let request = pipeline.request(for: context) else {
            return .hide
        }
        return .load(request, context)
    }
}
