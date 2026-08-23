import AppKit
import ApplicationServices

struct AccessibilityCellSnapshot: Equatable, Sendable {
    let text: String?
    let frame: CGRect?
}

protocol AccessibilityClient {
    func isTrusted() -> Bool
    func currentCellSnapshot() -> AccessibilityCellSnapshot?
}

struct SystemAccessibilityClient: AccessibilityClient {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func currentCellSnapshot() -> AccessibilityCellSnapshot? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success else {
            return nil
        }

        guard let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)

        let rawText = copyAttribute(kAXValueAttribute as CFString, from: focusedElement)
            ?? copyAttribute(kAXTitleAttribute as CFString, from: focusedElement)
            ?? copyAttribute(kAXDescriptionAttribute as CFString, from: focusedElement)
        let text = (rawText as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let frame = copyFrame(from: focusedElement)
        return AccessibilityCellSnapshot(text: text?.isEmpty == true ? nil : text, frame: frame)
    }

    private func copyAttribute(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyFrame(from element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(kAXPositionAttribute as CFString, from: element),
              let sizeValue = copyAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }

        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let position = unsafeBitCast(positionValue, to: AXValue.self)
        let size = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetType(position) == .cgPoint,
              AXValueGetType(size) == .cgSize else { return nil }

        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}

protocol ClipboardFallback {
    func readCurrentCellText() async -> String?
}

struct SystemClipboardFallback: ClipboardFallback {
    private let timeout: TimeInterval = 0.3

    func readCurrentCellText() async -> String? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased()
            == "com.kingsoft.wpsoffice.mac" else {
            return nil
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let originalChangeCount = pasteboard.changeCount
        defer { restore(snapshot, to: pasteboard) }

        postCommandC()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != originalChangeCount {
                return pasteboard.string(forType: .string)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private func postCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [String: Data]()) { values, type in
                if let data = item.data(forType: type) {
                    values[type.rawValue] = data
                }
            }
        } ?? []
    }

    private func restore(_ snapshot: [[String: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { values in
            let item = NSPasteboardItem()
            values.forEach { type, data in
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

struct WPSAdapter: SpreadsheetAdapter {
    let app: SpreadsheetApp = .wps
    let capability = AdapterCapability(
        canReadTextDirectly: true,
        canReadCellFrame: true,
        canReadRowColumn: false,
        needsClipboardFallback: true
    )

    private let accessibilityClient: AccessibilityClient
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let clipboardFallback: ClipboardFallback

    init(
        accessibilityClient: AccessibilityClient = SystemAccessibilityClient(),
        activeApplicationDetector: ActiveApplicationDetecting = ActiveAppDetector(),
        clipboardFallback: ClipboardFallback = SystemClipboardFallback()
    ) {
        self.accessibilityClient = accessibilityClient
        self.activeApplicationDetector = activeApplicationDetector
        self.clipboardFallback = clipboardFallback
    }

    func isAvailable() -> Bool {
        activeApplicationDetector.activeSpreadsheetApp() == .wps
            && accessibilityClient.isTrusted()
    }

    func currentCell() async -> CellContext? {
        guard isAvailable() else { return nil }

        if let context = currentAccessibleCell() { return context }

        let snapshot = accessibilityClient.currentCellSnapshot()

        guard let fallbackText = normalized(await clipboardFallback.readCurrentCellText()) else {
            return nil
        }
        return CellContext(text: fallbackText, frame: snapshot?.frame, app: .wps, row: nil, column: nil)
    }

    /// Reads only Accessibility data. The preview timer uses this path so it never
    /// synthesizes Command-C or modifies the user's clipboard while polling.
    func currentAccessibleCell() -> CellContext? {
        guard isAvailable() else { return nil }
        let snapshot = accessibilityClient.currentCellSnapshot()
        guard let text = normalized(snapshot?.text) else { return nil }
        return CellContext(text: text, frame: snapshot?.frame, app: .wps, row: nil, column: nil)
    }

    private func normalized(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
