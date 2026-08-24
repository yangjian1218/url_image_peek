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

    func testKeyboardShortcutStatusDoesNotRequestPermission() {
        let accessibilityChecker = AccessibilityCheckerSpy(isTrusted: true)
        let keyboardChecker = KeyboardShortcutCheckerSpy(isTrusted: true)
        let manager = PermissionManager(
            checker: accessibilityChecker,
            keyboardShortcutChecker: keyboardChecker
        )

        XCTAssertTrue(manager.isKeyboardShortcutAccessGranted)
        XCTAssertEqual(keyboardChecker.requestCount, 0)
    }

    func testKeyboardShortcutRequestDelegatesExactlyOnce() {
        let keyboardChecker = KeyboardShortcutCheckerSpy(isTrusted: false)
        let manager = PermissionManager(keyboardShortcutChecker: keyboardChecker)

        manager.requestKeyboardShortcutAccess()

        XCTAssertEqual(keyboardChecker.requestCount, 1)
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

private final class KeyboardShortcutCheckerSpy: KeyboardShortcutAccessChecking {
    private let trusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool) {
        self.trusted = isTrusted
    }

    func isTrusted() -> Bool { trusted }

    func requestTrustPrompt() {
        requestCount += 1
    }
}
