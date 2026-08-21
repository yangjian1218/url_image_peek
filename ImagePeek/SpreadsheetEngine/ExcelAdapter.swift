protocol ExcelCellTextFallback {
    func readCurrentCellText() async -> String?
}

struct UnavailableExcelCellTextFallback: ExcelCellTextFallback {
    func readCurrentCellText() async -> String? { nil }
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
        fallback: ExcelCellTextFallback = UnavailableExcelCellTextFallback()
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
        return CellContext(text: text, frame: snapshot?.frame, app: .excel, row: nil, column: nil)
    }

    private func normalized(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
