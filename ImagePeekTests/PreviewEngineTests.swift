import XCTest
@testable import ImagePeek

final class PreviewEngineTests: XCTestCase {
    func testPreviewLayoutPlacesPanelToRightOfCellWhenItFits() {
        let frame = PreviewLayout.frame(
            cellFrame: CGRect(x: 100, y: 200, width: 80, height: 20),
            fallbackPoint: nil,
            panelSize: CGSize(width: 200, height: 160),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame.origin.x, 192)
        XCTAssertEqual(frame.origin.y, 130)
    }

    func testPreviewLayoutPlacesPanelToLeftWhenRightSideOverflows() {
        let frame = PreviewLayout.frame(
            cellFrame: CGRect(x: 700, y: 200, width: 80, height: 20),
            fallbackPoint: nil,
            panelSize: CGSize(width: 200, height: 160),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame.origin.x, 488)
        XCTAssertEqual(frame.origin.y, 130)
    }

    func testPreviewLayoutKeepsFallbackPanelWithinVisibleScreen() {
        let frame = PreviewLayout.frame(
            cellFrame: nil,
            fallbackPoint: CGPoint(x: 790, y: 10),
            panelSize: CGSize(width: 200, height: 160),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame, CGRect(x: 600, y: 0, width: 200, height: 160))
    }

    func testPreviewZoomClampsToSafeRange() {
        XCTAssertEqual(PreviewZoom.clamped(0.25), 0.5)
        XCTAssertEqual(PreviewZoom.clamped(2), 2)
        XCTAssertEqual(PreviewZoom.clamped(6), 5)
    }

    func testShortcutPolicyAllowsOnlyPreviewContextInSupportedSpreadsheet() {
        XCTAssertTrue(PreviewShortcutPolicy.canHandle(.space, app: .wps, hasPreview: true))
        XCTAssertTrue(PreviewShortcutPolicy.canHandle(.escape, app: .excel, hasPreview: true))
        XCTAssertFalse(PreviewShortcutPolicy.canHandle(.space, app: nil, hasPreview: true))
        XCTAssertFalse(PreviewShortcutPolicy.canHandle(.space, app: .wps, hasPreview: false))
    }

    func testShortcutPolicyRejectsBareLetters() {
        XCTAssertFalse(PreviewShortcutPolicy.canHandle(.letter("p"), app: .wps, hasPreview: true))
    }

    func testSettingsStorePersistsAndRestoresSettings() {
        let suiteName = "ImagePeekTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(userDefaults: defaults)
        let settings = ImagePeekSettings(automaticPreview: false, launchAtLogin: true, imageColumn: 3)

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testImageColumnFilterIncludesOnlyConfiguredColumn() {
        XCTAssertTrue(ImageColumnFilter(column: 3).includes(column: 3))
        XCTAssertFalse(ImageColumnFilter(column: 3).includes(column: 2))
        XCTAssertTrue(ImageColumnFilter.all.includes(column: nil))
    }
}
