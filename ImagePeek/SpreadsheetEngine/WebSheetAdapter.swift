import AppKit
import ApplicationServices

struct WebSheetCellSnapshot: Equatable, Sendable {
    let pageURL: URL
    let address: String
    let text: String
    let frame: CGRect?
}

protocol WebSheetAccessibilityClient {
    var lastReadStatus: WebSheetReadStatus { get }
    func isTrusted() -> Bool
    func currentCellSnapshot() -> WebSheetCellSnapshot?
}

enum WebSheetReadStatus: Equatable, Sendable {
    case idle
    case unsupportedPage
    case missingCellAddress
    case missingImageURL
    case matched(address: String)

    var message: String {
        switch self {
        case .idle: return "Waiting for a Chrome Feishu sheet cell."
        case .unsupportedPage: return "Chrome is not on a supported Feishu sheet."
        case .missingCellAddress: return "Feishu cell address was not exposed by Accessibility."
        case .missingImageURL: return "No image URL was found for the focused Feishu cell."
        case let .matched(address): return "Read Feishu cell \(address)."
        }
    }
}

final class SystemWebSheetAccessibilityClient: WebSheetAccessibilityClient {
    private(set) var lastReadStatus: WebSheetReadStatus = .idle

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func currentCellSnapshot() -> WebSheetCellSnapshot? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.bundleIdentifier?.lowercased() == "com.google.chrome" else {
            lastReadStatus = .unsupportedPage
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        let result = WebSheetAccessibilitySnapshotParser.result(from: collectStrings(from: applicationElement))
        lastReadStatus = result.status
        return result.snapshot
    }

    private func collectStrings(from root: AXUIElement) -> [String] {
        var pending = [root]
        var strings: [String] = []
        var visited = 0

        while let element = pending.popLast(), visited < 2_000 {
            visited += 1
            for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let value = copyAttribute(attribute as CFString, from: element) as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    strings.append(value)
                }
            }
            if let children = copyAttribute(kAXChildrenAttribute as CFString, from: element) {
                pending.append(contentsOf: accessibilityElements(from: children))
            }
        }
        return strings
    }

    private func copyAttribute(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func accessibilityElements(from value: CFTypeRef) -> [AXUIElement] {
        guard let values = value as? [CFTypeRef] else { return [] }
        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
    }
}

enum WebSheetAccessibilitySnapshotParser {
    struct Result {
        let snapshot: WebSheetCellSnapshot?
        let status: WebSheetReadStatus
    }

    static func snapshot(from strings: [String]) -> WebSheetCellSnapshot? {
        result(from: strings).snapshot
    }

    static func result(from strings: [String]) -> Result {
        guard let pageURL = strings.lazy.compactMap(normalizedPageURL).first(where: WebSheetURLPolicy.isSupported) else {
            return Result(snapshot: nil, status: .unsupportedPage)
        }

        for (index, value) in strings.enumerated() where A1CellReference.parse(value) != nil {
            let cellValues = strings.dropFirst(index + 1).prefix(8)
            if let text = cellValues.first(where: { ImageSourceResolver().resolve($0) != nil }) {
                return Result(
                    snapshot: WebSheetCellSnapshot(pageURL: pageURL, address: value, text: text, frame: nil),
                    status: .matched(address: value)
                )
            }
        }
        let containsAddress = strings.contains { A1CellReference.parse($0) != nil }
        return Result(snapshot: nil, status: containsAddress ? .missingImageURL : .missingCellAddress)
    }

    private static func normalizedPageURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host != nil { return url }
        guard trimmed.contains(".feishu.cn/") else { return nil }
        return URL(string: "https://" + trimmed)
    }
}

struct A1CellReference: Equatable, Sendable {
    let row: Int
    let column: Int

    static func parse(_ value: String) -> A1CellReference? {
        let letters = value.prefix { $0.isASCII && $0.isLetter }
        let digits = value.dropFirst(letters.count)
        guard (1...3).contains(letters.count),
              !digits.isEmpty,
              let row = Int(digits),
              row > 0,
              digits.allSatisfy(\.isNumber) else {
            return nil
        }

        let column = letters.uppercased().unicodeScalars.reduce(0) { result, scalar in
            result * 26 + Int(scalar.value - 64)
        }
        return column > 0 ? A1CellReference(row: row, column: column) : nil
    }
}

enum WebSheetURLPolicy {
    static func isSupported(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".feishu.cn") && url.path.hasPrefix("/sheets/")
    }
}

struct WebSheetAdapter: SpreadsheetAdapter {
    let app: SpreadsheetApp = .feishuChrome
    let capability = AdapterCapability(
        canReadTextDirectly: true,
        canReadCellFrame: false,
        canReadRowColumn: true,
        needsClipboardFallback: false
    )

    private let client: WebSheetAccessibilityClient
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let resolver: ImageSourceResolver

    init(
        client: WebSheetAccessibilityClient = SystemWebSheetAccessibilityClient(),
        activeApplicationDetector: ActiveApplicationDetecting = ActiveAppDetector(),
        resolver: ImageSourceResolver = ImageSourceResolver()
    ) {
        self.client = client
        self.activeApplicationDetector = activeApplicationDetector
        self.resolver = resolver
    }

    func isAvailable() -> Bool {
        activeApplicationDetector.activeSpreadsheetApp() == .feishuChrome && client.isTrusted()
    }

    var lastReadStatus: WebSheetReadStatus {
        client.lastReadStatus
    }

    func currentCell() async -> CellContext? {
        guard isAvailable(),
              let snapshot = client.currentCellSnapshot(),
              WebSheetURLPolicy.isSupported(snapshot.pageURL),
              let reference = A1CellReference.parse(snapshot.address),
              resolver.resolve(snapshot.text) != nil else {
            return nil
        }
        return CellContext(
            text: snapshot.text,
            frame: snapshot.frame,
            app: .feishuChrome,
            row: reference.row,
            column: reference.column
        )
    }
}
