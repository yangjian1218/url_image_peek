import XCTest
@testable import ImagePeek

final class SpreadsheetCoreTests: XCTestCase {
    func testClassifiesInstalledWPSBundleIdentifier() {
        XCTAssertEqual(
            ActiveAppDetector.classify(bundleIdentifier: "com.kingsoft.wpsoffice.mac"),
            .wps
        )
    }

    func testClassifiesInstalledExcelBundleIdentifierCaseInsensitively() {
        XCTAssertEqual(
            ActiveAppDetector.classify(bundleIdentifier: "com.microsoft.Excel"),
            .excel
        )
    }

    func testRejectsUnknownAndMissingBundleIdentifiers() {
        XCTAssertNil(ActiveAppDetector.classify(bundleIdentifier: "com.apple.TextEdit"))
        XCTAssertNil(ActiveAppDetector.classify(bundleIdentifier: nil))
    }

    func testWPSAdapterStartsAsSafeNoOp() async {
        let adapter = WPSAdapter()

        XCTAssertEqual(adapter.app, .wps)
        XCTAssertFalse(adapter.isAvailable())
        XCTAssertEqual(adapter.capability, .safeNoOp)
        let cell = await adapter.currentCell()
        XCTAssertNil(cell)
    }

    func testExcelAdapterStartsAsSafeNoOp() async {
        let adapter = ExcelAdapter()

        XCTAssertEqual(adapter.app, .excel)
        XCTAssertFalse(adapter.isAvailable())
        XCTAssertEqual(adapter.capability, .safeNoOp)
        let cell = await adapter.currentCell()
        XCTAssertNil(cell)
    }
}
