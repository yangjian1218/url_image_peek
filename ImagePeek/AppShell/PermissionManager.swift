import ApplicationServices

protocol AccessibilityChecking {
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

final class PermissionManager {
    private let checker: AccessibilityChecking

    init(checker: AccessibilityChecking = SystemAccessibilityChecker()) {
        self.checker = checker
    }

    var isAccessibilityGranted: Bool {
        checker.isTrusted()
    }

    func requestAccessibility() {
        checker.requestTrustPrompt()
    }
}
