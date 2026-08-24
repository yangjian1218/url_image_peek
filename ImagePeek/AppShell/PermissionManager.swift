import ApplicationServices

protocol AccessibilityChecking {
    func isTrusted() -> Bool
    func requestTrustPrompt()
}

protocol KeyboardShortcutAccessChecking {
    func isTrusted() -> Bool
    func requestTrustPrompt()
}

struct SystemAccessibilityChecker: AccessibilityChecking {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestTrustPrompt() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

struct SystemKeyboardShortcutAccessChecker: KeyboardShortcutAccessChecking {
    func isTrusted() -> Bool {
        CGPreflightListenEventAccess()
    }

    func requestTrustPrompt() {
        CGRequestListenEventAccess()
    }
}

final class PermissionManager {
    private let checker: AccessibilityChecking
    private let keyboardShortcutChecker: KeyboardShortcutAccessChecking

    init(
        checker: AccessibilityChecking = SystemAccessibilityChecker(),
        keyboardShortcutChecker: KeyboardShortcutAccessChecking = SystemKeyboardShortcutAccessChecker()
    ) {
        self.checker = checker
        self.keyboardShortcutChecker = keyboardShortcutChecker
    }

    var isAccessibilityGranted: Bool {
        checker.isTrusted()
    }

    func requestAccessibility() {
        checker.requestTrustPrompt()
    }

    var isKeyboardShortcutAccessGranted: Bool {
        keyboardShortcutChecker.isTrusted()
    }

    func requestKeyboardShortcutAccess() {
        keyboardShortcutChecker.requestTrustPrompt()
    }
}
