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
        let adapter = WPSAdapter(
            accessibilityClient: FakeAccessibilityClient(isTrusted: false, snapshot: nil),
            activeApplicationDetector: FakeActiveApplicationDetector(app: nil),
            clipboardFallback: ClipboardFallbackSpy(result: nil)
        )

        XCTAssertEqual(adapter.app, .wps)
        XCTAssertFalse(adapter.isAvailable())
        XCTAssertEqual(
            adapter.capability,
            AdapterCapability(
                canReadTextDirectly: true,
                canReadCellFrame: true,
                canReadRowColumn: false,
                needsClipboardFallback: true
            )
        )
        let cell = await adapter.currentCell()
        XCTAssertNil(cell)
    }

    func testWPSReadsAccessibilityTextAndFrameWithoutClipboardFallback() async {
        let fallback = ClipboardFallbackSpy(result: "should not be used")
        let adapter = WPSAdapter(
            accessibilityClient: FakeAccessibilityClient(
                isTrusted: true,
                snapshot: AccessibilityCellSnapshot(
                    text: "https://example.com/image.jpg",
                    frame: CGRect(x: 40, y: 50, width: 80, height: 20)
                )
            ),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .wps),
            clipboardFallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertEqual(cell?.text, "https://example.com/image.jpg")
        XCTAssertEqual(cell?.frame, CGRect(x: 40, y: 50, width: 80, height: 20))
        XCTAssertEqual(cell?.app, .wps)
        XCTAssertEqual(fallback.callCount, 0)
    }

    func testWPSUsesClipboardFallbackWhenAccessibilityHasNoText() async {
        let fallback = ClipboardFallbackSpy(result: "/Users/test/Pictures/image.png")
        let adapter = WPSAdapter(
            accessibilityClient: FakeAccessibilityClient(
                isTrusted: true,
                snapshot: AccessibilityCellSnapshot(
                    text: nil,
                    frame: CGRect(x: 10, y: 20, width: 80, height: 20)
                )
            ),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .wps),
            clipboardFallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertEqual(cell?.text, "/Users/test/Pictures/image.png")
        XCTAssertEqual(cell?.frame, CGRect(x: 10, y: 20, width: 80, height: 20))
        XCTAssertEqual(fallback.callCount, 1)
    }

    func testWPSDoesNotReadOrFallbackWhenInactiveOrUntrusted() async {
        let fallback = ClipboardFallbackSpy(result: "https://example.com/image.jpg")
        let adapter = WPSAdapter(
            accessibilityClient: FakeAccessibilityClient(isTrusted: false, snapshot: nil),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .excel),
            clipboardFallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertNil(cell)
        XCTAssertEqual(fallback.callCount, 0)
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

private struct FakeActiveApplicationDetector: ActiveApplicationDetecting {
    let app: SpreadsheetApp?

    func activeSpreadsheetApp() -> SpreadsheetApp? { app }
}

private struct FakeAccessibilityClient: AccessibilityClient {
    let trusted: Bool
    let snapshot: AccessibilityCellSnapshot?

    init(isTrusted: Bool, snapshot: AccessibilityCellSnapshot?) {
        trusted = isTrusted
        self.snapshot = snapshot
    }

    func isTrusted() -> Bool { trusted }

    func currentCellSnapshot() -> AccessibilityCellSnapshot? { snapshot }
}

private final class ClipboardFallbackSpy: ClipboardFallback {
    let result: String?
    private(set) var callCount = 0

    init(result: String?) {
        self.result = result
    }

    func readCurrentCellText() async -> String? {
        callCount += 1
        return result
    }
}
