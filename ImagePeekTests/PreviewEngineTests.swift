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

    func testPreviewLayoutPlacesFallbackPanelToLeftWhenRightSideOverflows() {
        let frame = PreviewLayout.frame(
            cellFrame: nil,
            fallbackPoint: CGPoint(x: 790, y: 10),
            panelSize: CGSize(width: 200, height: 160),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame, CGRect(x: 578, y: 0, width: 200, height: 160))
    }

    func testPinnedPreviewLayoutPlacesPanelAtTopRightWithScreenInset() {
        let frame = PinnedPreviewLayout.frame(
            panelSize: CGSize(width: 200, height: 160),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(frame, CGRect(x: 576, y: 416, width: 200, height: 160))
    }

    func testPreviewZoomClampsToSafeRange() {
        XCTAssertEqual(PreviewZoom.clamped(0.25), 0.5)
        XCTAssertEqual(PreviewZoom.clamped(2), 2)
        XCTAssertEqual(PreviewZoom.clamped(6), 5)
    }

    func testPreviewImageLayoutFitsWholeImageAtDefaultZoom() {
        let size = PreviewImageLayout.displaySize(
            imageSize: CGSize(width: 1200, height: 1800),
            availableSize: CGSize(width: 320, height: 260),
            zoom: 1
        )

        XCTAssertEqual(size.width, 173.33333333333334, accuracy: 0.0001)
        XCTAssertEqual(size.height, 260, accuracy: 0.0001)
    }

    func testPreviewImageLayoutExpandsFromFittedSizeWhenZoomed() {
        let size = PreviewImageLayout.displaySize(
            imageSize: CGSize(width: 1200, height: 1800),
            availableSize: CGSize(width: 320, height: 260),
            zoom: 2
        )

        XCTAssertEqual(size.width, 346.6666666666667, accuracy: 0.0001)
        XCTAssertEqual(size.height, 520, accuracy: 0.0001)
    }

    func testPreviewImageInfoFormatsPixelDimensions() {
        XCTAssertEqual(PreviewImageInfo.pixelSizeText(for: CGSize(width: 900, height: 1200)), "900 × 1200 px")
    }

    func testPreviewImageInfoPlacesCaptionInsideBottomOfPanel() {
        XCTAssertEqual(
            PreviewImageInfo.captionFrame(containerSize: CGSize(width: 320, height: 480)),
            CGRect(x: 8, y: 8, width: 304, height: 20)
        )
    }

    func testPreviewDismissalSuppressesOnlyTheDismissedSelection() {
        let dismissed = CellContext(text: "https://example.com/a.jpg", frame: nil, app: .excel, row: 2, column: 3)
        let other = CellContext(text: "https://example.com/b.jpg", frame: nil, app: .excel, row: 3, column: 3)

        XCTAssertTrue(PreviewDismissalPolicy.shouldSuppressLoad(context: dismissed, dismissedContext: dismissed))
        XCTAssertFalse(PreviewDismissalPolicy.shouldSuppressLoad(context: other, dismissedContext: dismissed))
    }

    func testPreviewScrollPolicyHidesScrollersAtDefaultZoomAndShowsAfterZoomingIn() {
        XCTAssertFalse(PreviewScrollPolicy.showsScrollers(for: 1))
        XCTAssertFalse(PreviewScrollPolicy.showsScrollers(for: 0.8))
        XCTAssertTrue(PreviewScrollPolicy.showsScrollers(for: 1.01))
    }

    func testPreviewPanelLayoutUsesPortraitAspectWithoutEmptySideArea() {
        XCTAssertEqual(
            PreviewPanelLayout.contentSize(for: CGSize(width: 1200, height: 1800)),
            CGSize(width: 320, height: 480)
        )
    }

    func testPreviewPanelLayoutUsesLandscapeAspectWithoutEmptySideArea() {
        XCTAssertEqual(
            PreviewPanelLayout.contentSize(for: CGSize(width: 1800, height: 1200)),
            CGSize(width: 360, height: 240)
        )
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

    func testShortcutPolicyAllowsAllDocumentedActionsForExcelPreview() {
        for shortcut in [PreviewShortcut.space, .optionC, .optionO, .optionR, .optionP] {
            XCTAssertTrue(PreviewShortcutPolicy.canHandle(shortcut, app: .excel, hasPreview: true))
        }
    }

    func testKeyboardShortcutEventTapCanStartWithAccessibilityPermission() {
        XCTAssertTrue(KeyboardShortcutEventTapPolicy.canStart(accessibilityGranted: true))
        XCTAssertFalse(KeyboardShortcutEventTapPolicy.canStart(accessibilityGranted: false))
    }

    func testKeyboardShortcutEventTapRequestsAccessibilityWhenItIsUnavailable() {
        XCTAssertEqual(
            KeyboardShortcutEventTapPolicy.startAction(accessibilityGranted: false),
            .requestAccessibility
        )
        XCTAssertEqual(
            KeyboardShortcutEventTapPolicy.startAction(accessibilityGranted: true),
            .start
        )
    }

    func testShortcutResolverRecognizesOnlyDocumentedConditionalShortcuts() {
        XCTAssertEqual(PreviewShortcutResolver.shortcut(keyCode: 49, modifiers: []), .space)
        XCTAssertEqual(PreviewShortcutResolver.shortcut(keyCode: 53, modifiers: []), .escape)
        XCTAssertEqual(PreviewShortcutResolver.shortcut(keyCode: 8, modifiers: .option), .optionC)
        XCTAssertEqual(PreviewShortcutResolver.shortcut(keyCode: 31, modifiers: .option), .optionO)
        XCTAssertEqual(PreviewShortcutResolver.shortcut(keyCode: 15, modifiers: .option), .optionR)
        XCTAssertEqual(PreviewShortcutResolver.shortcut(keyCode: 35, modifiers: .option), .optionP)
        XCTAssertNil(PreviewShortcutResolver.shortcut(keyCode: 35, modifiers: []))
    }

    func testSettingsStorePersistsAndRestoresSettings() {
        let suiteName = "ImagePeekTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(userDefaults: defaults)
        let settings = ImagePeekSettings(
            automaticPreview: false,
            launchAtLogin: true,
            imageColumn: 3,
            wpsClipboardFallback: false
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testSettingsDecodeMissingOperationsFieldsWithSafeDefaults() throws {
        let data = Data(#"{"automaticPreview":true,"launchAtLogin":false,"wpsClipboardFallback":true}"#.utf8)

        let settings = try JSONDecoder().decode(ImagePeekSettings.self, from: data)

        XCTAssertTrue(settings.showsPixelDimensions)
        XCTAssertFalse(settings.showsLoadSource)
        XCTAssertEqual(settings.cachePolicy.byteLimit, 1_073_741_824)
        XCTAssertEqual(settings.cachePolicy.maximumAge, 30 * 24 * 60 * 60)
    }

    func testDiagnosticsDoesNotCountCancellationAsFailure() {
        var diagnostics = RuntimeDiagnostics()

        diagnostics.record(.success(source: .memoryCache, elapsed: 0.012))
        diagnostics.record(.cancelled)

        XCTAssertEqual(diagnostics.snapshot.memoryCacheHitCount, 1)
        XCTAssertEqual(diagnostics.snapshot.failureCount, 0)
        XCTAssertEqual(diagnostics.snapshot.lastResult, .cancelled)
    }

    @MainActor
    func testOperationsStatusStorePublishesLatestDiagnosticsSnapshot() {
        let store = OperationsStatusStore()

        store.updateDiagnostics(RuntimeDiagnosticsSnapshot(networkLoadCount: 1))

        XCTAssertEqual(store.diagnostics.networkLoadCount, 1)
    }

    func testImageColumnFilterIncludesOnlyConfiguredColumn() {
        XCTAssertTrue(ImageColumnFilter(column: 3).includes(column: 3))
        XCTAssertFalse(ImageColumnFilter(column: 3).includes(column: 2))
        XCTAssertTrue(ImageColumnFilter.all.includes(column: nil))
    }

    func testImageColumnInputUsesBlankForAllColumnsAndPositiveValuesForFiltering() {
        XCTAssertNil(ImageColumnInput.column(from: "  "))
        XCTAssertEqual(ImageColumnInput.column(from: "3"), 3)
        XCTAssertNil(ImageColumnInput.column(from: "0"))
        XCTAssertNil(ImageColumnInput.column(from: "column C"))
        XCTAssertEqual(ImageColumnInput.text(for: 3), "3")
        XCTAssertEqual(ImageColumnInput.text(for: nil), "")
    }

    func testLaunchAtLoginControllerDelegatesRequestedState() {
        let service = LaunchAtLoginServiceSpy()
        let controller = LaunchAtLoginController(service: service)

        XCTAssertTrue(controller.apply(enabled: true))
        XCTAssertEqual(service.requests, [true])
        XCTAssertTrue(controller.apply(enabled: false))
        XCTAssertEqual(service.requests, [true, false])
    }

    func testLaunchAtLoginControllerReportsServiceFailure() {
        let service = LaunchAtLoginServiceSpy(error: LaunchAtLoginServiceSpy.Error.denied)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertFalse(controller.apply(enabled: true))
        XCTAssertEqual(service.requests, [true])
    }
}

private final class LaunchAtLoginServiceSpy: LaunchAtLoginServicing {
    enum Error: Swift.Error {
        case denied
    }

    let error: Swift.Error?
    private(set) var requests: [Bool] = []

    init(error: Swift.Error? = nil) {
        self.error = error
    }

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if let error { throw error }
    }
}
