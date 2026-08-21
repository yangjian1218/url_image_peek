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
}
