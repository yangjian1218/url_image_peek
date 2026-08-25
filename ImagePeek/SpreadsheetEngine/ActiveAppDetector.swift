import AppKit

protocol ActiveApplicationDetecting {
    func activeSpreadsheetApp() -> SpreadsheetApp?
}

struct ActiveAppDetector: ActiveApplicationDetecting {
    private static let supportedBundleIdentifiers: [String: SpreadsheetApp] = [
        "com.kingsoft.wpsoffice.mac": .wps,
        "com.microsoft.excel": .excel,
        "com.google.chrome": .feishuChrome,
    ]

    private let bundleIdentifierProvider: () -> String?

    init(bundleIdentifierProvider: @escaping () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }) {
        self.bundleIdentifierProvider = bundleIdentifierProvider
    }

    static func classify(bundleIdentifier: String?) -> SpreadsheetApp? {
        guard let bundleIdentifier else { return nil }
        return supportedBundleIdentifiers[bundleIdentifier.lowercased()]
    }

    func activeSpreadsheetApp() -> SpreadsheetApp? {
        Self.classify(bundleIdentifier: bundleIdentifierProvider())
    }
}
