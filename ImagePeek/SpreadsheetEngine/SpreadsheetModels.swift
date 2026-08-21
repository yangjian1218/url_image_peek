import CoreGraphics

enum SpreadsheetApp: Equatable, Sendable {
    case wps
    case excel
}

struct CellContext: Equatable, Sendable {
    let text: String
    let frame: CGRect?
    let app: SpreadsheetApp
    let row: Int?
    let column: Int?
}

struct AdapterCapability: Equatable, Sendable {
    let canReadTextDirectly: Bool
    let canReadCellFrame: Bool
    let canReadRowColumn: Bool
    let needsClipboardFallback: Bool

    static let safeNoOp = AdapterCapability(
        canReadTextDirectly: false,
        canReadCellFrame: false,
        canReadRowColumn: false,
        needsClipboardFallback: false
    )
}
