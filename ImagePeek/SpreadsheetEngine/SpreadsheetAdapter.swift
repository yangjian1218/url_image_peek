protocol SpreadsheetAdapter: Sendable {
    var app: SpreadsheetApp { get }
    var capability: AdapterCapability { get }

    func isAvailable() -> Bool
    func currentCell() async -> CellContext?
}
