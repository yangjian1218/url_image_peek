import AppKit
import ApplicationServices

struct GlobalSelectedTextSnapshot: Equatable {
    let bundleIdentifier: String?
    let text: String
}

enum GlobalSelectionReadStatus: Equatable {
    case idle
    case waiting
    case accessibilityRequired
    case noFrontmostApplication
    case noFocusedElement
    case noSelectedText
    case invalidImageURL
    case selectionChanged
    case ready

    var message: String {
        switch self {
        case .idle:
            return "No selection checked yet."
        case .waiting:
            return "Waiting for the selected text to settle."
        case .accessibilityRequired:
            return "Accessibility permission is required."
        case .noFrontmostApplication:
            return "No frontmost application was found."
        case .noFocusedElement:
            return "No focused text element was exposed."
        case .noSelectedText:
            return "The focused element exposed no selected text."
        case .invalidImageURL:
            return "Selected text is not an image URL."
        case .selectionChanged:
            return "Selection changed before previewing."
        case .ready:
            return "Image previewed from the selected URL."
        }
    }
}

enum GlobalSelectedTextReadResult {
    case success(GlobalSelectedTextSnapshot)
    case failure(GlobalSelectionReadStatus)
}

protocol GlobalSelectedTextReading {
    func selectedTextSnapshot() -> GlobalSelectedTextReadResult
}

struct SystemGlobalSelectedTextReader: GlobalSelectedTextReading {
    func selectedTextSnapshot() -> GlobalSelectedTextReadResult {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityRequired)
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .failure(.noFrontmostApplication)
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
            return .failure(.noFocusedElement)
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
            return .failure(.noSelectedText)
        }

        return .success(GlobalSelectedTextSnapshot(bundleIdentifier: application.bundleIdentifier, text: text))
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
