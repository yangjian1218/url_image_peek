import AppKit

protocol ExcelCellTextFallback {
    func readCurrentCellText() async -> String?
}

struct SystemExcelCellTextFallback: ExcelCellTextFallback {
    func readCurrentCellText() async -> String? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == "com.microsoft.excel" else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            let result = NSAppleScript(source: Self.source)?.executeAndReturnError(&error)
            guard error == nil else { return nil }
            return result?.stringValue
        }.value
    }

    private static let source = """
    tell application id "com.microsoft.Excel"
        try
            return (value of active cell) as text
        on error
            return ""
        end try
    end tell
    """
}

struct ExcelAdapter: SpreadsheetAdapter {
    let app: SpreadsheetApp = .excel
    let capability = AdapterCapability(
        canReadTextDirectly: true,
        canReadCellFrame: true,
        canReadRowColumn: false,
        needsClipboardFallback: false
    )

    private let accessibilityClient: AccessibilityClient
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let fallback: ExcelCellTextFallback

    init(
        accessibilityClient: AccessibilityClient = SystemAccessibilityClient(),
        activeApplicationDetector: ActiveApplicationDetecting = ActiveAppDetector(),
        fallback: ExcelCellTextFallback = SystemExcelCellTextFallback()
    ) {
        self.accessibilityClient = accessibilityClient
        self.activeApplicationDetector = activeApplicationDetector
        self.fallback = fallback
    }

    func isAvailable() -> Bool {
        activeApplicationDetector.activeSpreadsheetApp() == .excel
            && accessibilityClient.isTrusted()
    }

    func currentCell() async -> CellContext? {
        guard isAvailable() else { return nil }
        let snapshot = accessibilityClient.currentCellSnapshot()
        let accessibilityText = normalized(snapshot?.text)
        let fallbackText = accessibilityText == nil ? normalized(await fallback.readCurrentCellText()) : nil
        let text = accessibilityText ?? fallbackText
        guard let text else { return nil }
        return CellContext(
            text: text,
            frame: trustedCellFrame(snapshot?.frame),
            app: .excel,
            row: nil,
            column: nil
        )
    }

    private func trustedCellFrame(_ frame: CGRect?) -> CGRect? {
        guard let frame,
              frame.width > 0,
              frame.height > 0,
              frame.width <= 500,
              frame.height <= 160 else {
            return nil
        }
        return frame
    }

    private func normalized(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
