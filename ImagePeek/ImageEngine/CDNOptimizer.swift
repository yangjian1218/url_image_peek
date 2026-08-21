import Foundation

protocol CDNOptimizationRule {
    func optimizedURL(for url: URL) -> URL?
}

struct AliyunOSSRule: CDNOptimizationRule {
    private let signatureParameterNames: Set<String> = [
        "ossaccesskeyid",
        "signature",
        "x-oss-signature",
        "x-oss-credential",
        "x-oss-security-token",
        "x-oss-expires",
    ]

    func optimizedURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host.contains(".aliyuncs.com"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let lowercasedNames = Set(queryItems.map { $0.name.lowercased() })
        guard !lowercasedNames.contains("x-oss-process"),
              lowercasedNames.isDisjoint(with: signatureParameterNames) else {
            return nil
        }

        var optimizedComponents = components
        optimizedComponents.queryItems = queryItems + [
            URLQueryItem(name: "x-oss-process", value: "image/resize,l_900")
        ]
        return optimizedComponents.url
    }
}

struct CDNOptimizer {
    private let rules: [CDNOptimizationRule]

    init(rules: [CDNOptimizationRule] = [AliyunOSSRule()]) {
        self.rules = rules
    }

    func optimizedURL(for url: URL) -> URL {
        rules.compactMap { $0.optimizedURL(for: url) }.first ?? url
    }
}
