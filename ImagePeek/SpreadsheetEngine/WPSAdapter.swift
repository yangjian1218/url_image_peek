struct WPSAdapter: SpreadsheetAdapter {
    let app: SpreadsheetApp = .wps
    let capability: AdapterCapability = .safeNoOp

    func isAvailable() -> Bool { false }

    func currentCell() async -> CellContext? { nil }
}
