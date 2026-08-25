import AppKit
import ApplicationServices

struct WebSheetCellSnapshot: Equatable, Sendable {
    let pageURL: URL
    let address: String
    let text: String
    let frame: CGRect?
}

protocol WebSheetAccessibilityClient {
    func isTrusted() -> Bool
    func currentCellSnapshot() -> WebSheetCellSnapshot?
}

struct SystemWebSheetAccessibilityClient: WebSheetAccessibilityClient {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func currentCellSnapshot() -> WebSheetCellSnapshot? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.bundleIdentifier?.lowercased() == "com.google.chrome" else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        return WebSheetAccessibilitySnapshotParser.snapshot(from: collectStrings(from: applicationElement))
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
    static func snapshot(from strings: [String]) -> WebSheetCellSnapshot? {
        guard let pageURL = strings.lazy.compactMap(normalizedPageURL).first(where: WebSheetURLPolicy.isSupported) else {
            return nil
        }

        for (index, value) in strings.enumerated() where A1CellReference.parse(value) != nil {
            let cellValues = strings.dropFirst(index + 1).prefix(8)
            if let text = cellValues.first(where: { ImageSourceResolver().resolve($0) != nil }) {
                return WebSheetCellSnapshot(pageURL: pageURL, address: value, text: text, frame: nil)
            }
        }
        return nil
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
        let letters = value.prefix { $0.isLetter }
        let digits = value.dropFirst(letters.count)
        guard !letters.isEmpty,
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
