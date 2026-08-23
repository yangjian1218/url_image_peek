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

    func testWPSClipboardFallbackRejectsLargeAccessibilityGroupFrame() async {
        let fallback = ClipboardFallbackSpy(result: "https://example.com/image.jpg")
        let adapter = WPSAdapter(
            accessibilityClient: FakeAccessibilityClient(
                isTrusted: true,
                snapshot: AccessibilityCellSnapshot(
                    text: nil,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
                )
            ),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .wps),
            clipboardFallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertEqual(cell?.text, "https://example.com/image.jpg")
        XCTAssertNil(cell?.frame)
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

    func testExcelAdapterIsUnavailableWhenInactiveOrUntrusted() async {
        let adapter = ExcelAdapter(
            accessibilityClient: FakeAccessibilityClient(isTrusted: false, snapshot: nil),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .wps)
        )

        XCTAssertEqual(adapter.app, .excel)
        XCTAssertFalse(adapter.isAvailable())
        let cell = await adapter.currentCell()
        XCTAssertNil(cell)
    }

    func testExcelReadsAccessibilityTextBeforeFallback() async {
        let fallback = ExcelFallbackSpy(result: "fallback")
        let adapter = ExcelAdapter(
            accessibilityClient: FakeAccessibilityClient(
                isTrusted: true,
                snapshot: AccessibilityCellSnapshot(
                    text: " https://example.com/excel.jpg ",
                    frame: CGRect(x: 20, y: 30, width: 80, height: 20)
                )
            ),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .excel),
            fallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertEqual(cell?.text, "https://example.com/excel.jpg")
        XCTAssertEqual(cell?.frame, CGRect(x: 20, y: 30, width: 80, height: 20))
        XCTAssertEqual(fallback.callCount, 0)
    }

    func testExcelUsesAdapterFallbackWhenAccessibilityHasNoText() async {
        let fallback = ExcelFallbackSpy(result: "https://example.com/fallback.jpg")
        let adapter = ExcelAdapter(
            accessibilityClient: FakeAccessibilityClient(
                isTrusted: true,
                snapshot: AccessibilityCellSnapshot(text: nil, frame: nil)
            ),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .excel),
            fallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertEqual(cell?.text, "https://example.com/fallback.jpg")
        XCTAssertEqual(cell?.app, .excel)
        XCTAssertEqual(fallback.callCount, 1)
    }

    func testExcelFallbackRejectsLargeAccessibilityGroupFrame() async {
        let fallback = ExcelFallbackSpy(result: "https://example.com/fallback.jpg")
        let adapter = ExcelAdapter(
            accessibilityClient: FakeAccessibilityClient(
                isTrusted: true,
                snapshot: AccessibilityCellSnapshot(
                    text: nil,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
                )
            ),
            activeApplicationDetector: FakeActiveApplicationDetector(app: .excel),
            fallback: fallback
        )

        let cell = await adapter.currentCell()

        XCTAssertEqual(cell?.text, "https://example.com/fallback.jpg")
        XCTAssertNil(cell?.frame)
    }

    func testSelectionChangeRequestsCellReadForSupportedSpreadsheet() {
        var machine = NavigationStateMachine()

        let effect = machine.handle(.cellSelectionChanged(app: .wps))

        XCTAssertEqual(effect, .requestCellRead)
        XCTAssertEqual(machine.state, .awaitingCellRead(app: .wps))
    }

    func testSuccessfulCellReadShowsPreview() {
        var machine = NavigationStateMachine()
        let context = CellContext(text: "https://example.com/a.jpg", frame: nil, app: .wps, row: nil, column: nil)
        _ = machine.handle(.cellSelectionChanged(app: .wps))

        let effect = machine.handle(.cellReadCompleted(context))

        XCTAssertEqual(effect, .showPreview(context))
        XCTAssertEqual(machine.state, .visible(context))
    }

    func testEscHidesOnlyCurrentPreviewAndNextSelectionRequestsAgain() {
        var machine = NavigationStateMachine()
        let context = CellContext(text: "https://example.com/a.jpg", frame: nil, app: .wps, row: nil, column: nil)
        _ = machine.handle(.cellSelectionChanged(app: .wps))
        _ = machine.handle(.cellReadCompleted(context))

        XCTAssertEqual(machine.handle(.escape), .hidePreview)
        XCTAssertEqual(machine.state, .hidden(app: .wps))
        XCTAssertEqual(machine.handle(.cellSelectionChanged(app: .wps)), .requestCellRead)
    }

    func testLeavingSupportedAppsHidesPreviewAndStopsReading() {
        var machine = NavigationStateMachine()
        let context = CellContext(text: "https://example.com/a.jpg", frame: nil, app: .excel, row: nil, column: nil)
        _ = machine.handle(.cellSelectionChanged(app: .excel))
        _ = machine.handle(.cellReadCompleted(context))

        XCTAssertEqual(machine.handle(.activeApplicationChanged(nil)), .hidePreview)
        XCTAssertEqual(machine.state, .inactive)
    }

    func testNonImageOrFailedCellReadHidesPreviewWithoutDisablingAutomation() {
        var machine = NavigationStateMachine()
        _ = machine.handle(.cellSelectionChanged(app: .wps))

        XCTAssertEqual(machine.handle(.cellReadCompleted(nil)), .hidePreview)
        XCTAssertEqual(machine.state, .hidden(app: .wps))
        XCTAssertEqual(machine.handle(.cellSelectionChanged(app: .wps)), .requestCellRead)
    }

    func testWPSSelectionTriggerAllowsMouseReleaseButNotNavigationKeyDown() {
        XCTAssertTrue(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .mouseReleased, app: .wps))
        XCTAssertFalse(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyCode(123), app: .wps))
        XCTAssertFalse(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyCode(48), app: .wps))
        XCTAssertFalse(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyCode(36), app: .wps))
        XCTAssertTrue(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyReleased(123), app: .wps))
        XCTAssertTrue(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyReleased(48), app: .wps))
        XCTAssertTrue(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyReleased(36), app: .wps))
    }

    func testWPSSelectionTriggerRejectsOtherAppsAndOrdinaryTyping() {
        XCTAssertFalse(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .mouseReleased, app: .excel))
        XCTAssertFalse(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyCode(0), app: .wps))
        XCTAssertFalse(WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: .keyCode(49), app: .wps))
    }

    func testSpreadsheetSelectionTriggerRefreshesExcelAfterMouseAndNavigationKeyRelease() {
        XCTAssertTrue(SpreadsheetSelectionTriggerPolicy.shouldRequestRead(for: .mouseReleased, app: .excel))
        XCTAssertTrue(SpreadsheetSelectionTriggerPolicy.shouldRequestRead(for: .keyReleased(123), app: .excel))
        XCTAssertTrue(SpreadsheetSelectionTriggerPolicy.shouldRequestRead(for: .keyReleased(126), app: .excel))
        XCTAssertFalse(SpreadsheetSelectionTriggerPolicy.shouldRequestRead(for: .keyCode(123), app: .excel))
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

private final class ExcelFallbackSpy: ExcelCellTextFallback {
    let result: String?
    private(set) var callCount = 0

    init(result: String?) { self.result = result }

    func readCurrentCellText() async -> String? {
        callCount += 1
        return result
    }
}
