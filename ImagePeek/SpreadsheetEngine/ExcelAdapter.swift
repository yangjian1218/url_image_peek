struct ExcelAdapter: SpreadsheetAdapter {
    let app: SpreadsheetApp = .excel
    let capability: AdapterCapability = .safeNoOp

    func isAvailable() -> Bool { false }

    func currentCell() async -> CellContext? { nil }
}
