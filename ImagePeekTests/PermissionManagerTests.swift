import XCTest
@testable import ImagePeek

final class PermissionManagerTests: XCTestCase {
    func testReadingStatusDoesNotRequestPermission() {
        let checker = AccessibilityCheckerSpy(isTrusted: true)
        let manager = PermissionManager(checker: checker)

        XCTAssertTrue(manager.isAccessibilityGranted)
        XCTAssertEqual(checker.requestCount, 0)
    }

    func testExplicitRequestDelegatesExactlyOnce() {
        let checker = AccessibilityCheckerSpy(isTrusted: false)
        let manager = PermissionManager(checker: checker)

        manager.requestAccessibility()

        XCTAssertEqual(checker.requestCount, 1)
    }
}

private final class AccessibilityCheckerSpy: AccessibilityChecking {
    private let trusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool) {
        trusted = isTrusted
    }

    func isTrusted() -> Bool { trusted }

    func requestTrustPrompt() {
        requestCount += 1
    }
}
