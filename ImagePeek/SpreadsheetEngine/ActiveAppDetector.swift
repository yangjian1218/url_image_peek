import AppKit

struct ActiveAppDetector {
    private static let supportedBundleIdentifiers: [String: SpreadsheetApp] = [
        "com.kingsoft.wpsoffice.mac": .wps,
        "com.microsoft.excel": .excel,
    ]

    static func classify(bundleIdentifier: String?) -> SpreadsheetApp? {
        guard let bundleIdentifier else { return nil }
        return supportedBundleIdentifiers[bundleIdentifier.lowercased()]
    }

    func activeSpreadsheetApp() -> SpreadsheetApp? {
        Self.classify(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
