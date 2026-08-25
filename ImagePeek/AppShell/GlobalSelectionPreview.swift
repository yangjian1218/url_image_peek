import AppKit
import ApplicationServices

struct GlobalSelectedTextSnapshot: Equatable {
    let bundleIdentifier: String?
    let text: String
}

protocol GlobalSelectedTextReading {
    func selectedTextSnapshot() -> GlobalSelectedTextSnapshot?
}

struct SystemGlobalSelectedTextReader: GlobalSelectedTextReading {
    func selectedTextSnapshot() -> GlobalSelectedTextSnapshot? {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selectedTextValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        ) == .success,
        let text = (selectedTextValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty else {
            return nil
        }

        return GlobalSelectedTextSnapshot(bundleIdentifier: application.bundleIdentifier, text: text)
    }
}

enum GlobalSelectionPreviewPolicy {
    static func isEligible(selectedText: String) -> Bool {
        ImageSourceResolver().resolve(selectedText) != nil
    }

    static func shouldObserve(app: SpreadsheetApp?) -> Bool {
        app != .wps && app != .excel
    }
}

struct GlobalSelectionPreviewCoordinator {
    static let delay: TimeInterval = 1
}

enum GlobalSelectionPreviewEvent: Equatable {
    case mouseReleased
    case mousePressed
    case pointerMoved
    case pointerDragged
    case keyReleased
}

enum GlobalSelectionPreviewEventPolicy {
    static func shouldSchedule(for event: GlobalSelectionPreviewEvent) -> Bool {
        event == .mouseReleased
    }

    static func shouldCancel(for event: GlobalSelectionPreviewEvent) -> Bool {
        switch event {
        case .mouseReleased:
            return false
        case .mousePressed, .pointerMoved, .pointerDragged, .keyReleased:
            return true
        }
    }
}
