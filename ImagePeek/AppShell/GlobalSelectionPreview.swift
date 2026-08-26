import AppKit
import ApplicationServices

struct GlobalSelectedTextSnapshot: Equatable {
    let bundleIdentifier: String?
    let text: String
}

struct GlobalSelectionAccessibilityDiagnostics: Equatable {
    var focusedElementAvailable: Bool
    var scannedNodeCount: Int
    var selectedTextAttributeCount: Int
    var selectedTextRangeAttributeCount: Int
    var textMarkerRangeAttributeCount: Int
    var stringForRangeAttributeCount: Int
    var stringForTextMarkerRangeAttributeCount: Int
    var nonEmptySelectedRangeCount: Int
    var stringForRangeSuccessCount: Int
    var lastStringForRangeErrorCode: Int?

    static let empty = GlobalSelectionAccessibilityDiagnostics(
        focusedElementAvailable: false,
        scannedNodeCount: 0,
        selectedTextAttributeCount: 0,
        selectedTextRangeAttributeCount: 0,
        textMarkerRangeAttributeCount: 0,
        stringForRangeAttributeCount: 0,
        stringForTextMarkerRangeAttributeCount: 0,
        nonEmptySelectedRangeCount: 0,
        stringForRangeSuccessCount: 0,
        lastStringForRangeErrorCode: nil
    )

    var summary: String {
        "Focus: \(focusedElementAvailable ? "yes" : "no") · nodes: \(scannedNodeCount) · text: \(selectedTextAttributeCount) · range: \(selectedTextRangeAttributeCount) · marker: \(textMarkerRangeAttributeCount) · string-range: \(stringForRangeAttributeCount) · marker-string: \(stringForTextMarkerRangeAttributeCount) · active-range: \(nonEmptySelectedRangeCount) · string-ok: \(stringForRangeSuccessCount) · string-error: \(lastStringForRangeErrorCode.map(String.init) ?? "-")"
    }
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
    case frontmostApplicationChanged(from: String, to: String)
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
        case let .frontmostApplicationChanged(from, to):
            return "Frontmost app changed from \(from) to \(to)."
        case .ready:
            return "Image previewed from the selected URL."
        }
    }
}

enum GlobalSelectedTextReadResult {
    case success(GlobalSelectedTextSnapshot, GlobalSelectionAccessibilityDiagnostics)
    case failure(GlobalSelectionReadStatus, GlobalSelectionAccessibilityDiagnostics)
}

protocol GlobalSelectedTextReading {
    func selectedTextSnapshot() -> GlobalSelectedTextReadResult
}

struct SystemGlobalSelectedTextReader: GlobalSelectedTextReading {
    func selectedTextSnapshot() -> GlobalSelectedTextReadResult {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityRequired, .empty)
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .failure(.noFrontmostApplication, .empty)
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let hasFocusedElement = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success
        let focusedElement: AXUIElement?
        if hasFocusedElement,
           let focusedValue,
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        } else {
            focusedElement = nil
        }
        var diagnostics = GlobalSelectionAccessibilityDiagnostics.empty
        diagnostics.focusedElementAvailable = focusedElement != nil

        for scope in GlobalSelectionTextSearchPolicy.scopes(hasFocusedElement: focusedElement != nil) {
            let root: AXUIElement
            switch scope {
            case .focusedElement:
                guard let focusedElement else { continue }
                root = focusedElement
            case .application:
                root = applicationElement
            }
            if let text = selectedText(from: root, diagnostics: &diagnostics) {
                return .success(GlobalSelectedTextSnapshot(bundleIdentifier: application.bundleIdentifier, text: text), diagnostics)
            }
        }

        return .failure(focusedElement == nil ? .noFocusedElement : .noSelectedText, diagnostics)
    }

    private func selectedText(
        from root: AXUIElement,
        diagnostics: inout GlobalSelectionAccessibilityDiagnostics
    ) -> String? {
        var pending = [root]
        var visited = 0

        while let element = pending.popLast(), visited < GlobalSelectionTextSearchPolicy.maximumElementsPerRoot {
            visited += 1
            diagnostics.scannedNodeCount += 1
            recordCapabilities(of: element, diagnostics: &diagnostics)
            var selectedTextValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &selectedTextValue
            ) == .success,
            let text = GlobalSelectionTextSearchPolicy.firstSelection(in: [selectedTextValue as? String]) {
                return text
            }
            if let text = selectedTextForRange(from: element, diagnostics: &diagnostics) {
                return text
            }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let childrenValue {
                pending.append(contentsOf: AccessibilityTreeTraversalPolicy.pushOrder(accessibilityElements(from: childrenValue)))
            }
        }
        return nil
    }

    private func recordCapabilities(
        of element: AXUIElement,
        diagnostics: inout GlobalSelectionAccessibilityDiagnostics
    ) {
        var attributesValue: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributesValue) == .success,
           let attributes = attributesValue as? [String] {
            diagnostics.selectedTextAttributeCount += attributes.contains(kAXSelectedTextAttribute as String) ? 1 : 0
            diagnostics.selectedTextRangeAttributeCount += attributes.contains(kAXSelectedTextRangeAttribute as String) ? 1 : 0
            diagnostics.textMarkerRangeAttributeCount += attributes.contains("AXSelectedTextMarkerRange") ? 1 : 0
        }

        var parameterizedAttributesValue: CFArray?
        if AXUIElementCopyParameterizedAttributeNames(element, &parameterizedAttributesValue) == .success,
           let attributes = parameterizedAttributesValue as? [String] {
            diagnostics.stringForRangeAttributeCount += attributes.contains(kAXStringForRangeParameterizedAttribute as String) ? 1 : 0
            diagnostics.stringForTextMarkerRangeAttributeCount += attributes.contains("AXStringForTextMarkerRange") ? 1 : 0
        }
    }

    private func selectedTextForRange(
        from element: AXUIElement,
        diagnostics: inout GlobalSelectionAccessibilityDiagnostics
    ) -> String? {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
        let selectedRangeValue,
        CFGetTypeID(selectedRangeValue) == AXValueGetTypeID(),
        AXValueGetType(unsafeBitCast(selectedRangeValue, to: AXValue.self)) == .cfRange else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(
            unsafeBitCast(selectedRangeValue, to: AXValue.self),
            .cfRange,
            &selectedRange
        ), selectedRange.length > 0 else {
            return nil
        }
        diagnostics.nonEmptySelectedRangeCount += 1

        var selectedTextValue: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &selectedTextValue
        )
        guard error == .success else {
            diagnostics.lastStringForRangeErrorCode = Int(error.rawValue)
            return nil
        }
        diagnostics.stringForRangeSuccessCount += 1
        return GlobalSelectionTextSearchPolicy.firstSelection(in: [selectedTextValue as? String])
    }

    private func accessibilityElements(from value: CFTypeRef) -> [AXUIElement] {
        guard let values = value as? [CFTypeRef] else { return [] }
        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
    }
}

enum GlobalSelectionTextSearchPolicy {
    enum Scope: Equatable {
        case focusedElement
        case application
    }

    static let maximumElementsPerRoot = 128

    static func scopes(hasFocusedElement: Bool) -> [Scope] {
        hasFocusedElement ? [.focusedElement, .application] : [.application]
    }

    static func firstSelection(in candidates: [String?]) -> String? {
        candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
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
    static let delay: TimeInterval = 0.5
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
