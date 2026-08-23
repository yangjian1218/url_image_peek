enum NavigationEvent: Equatable {
    case cellSelectionChanged(app: SpreadsheetApp)
    case cellReadCompleted(CellContext?)
    case activeApplicationChanged(SpreadsheetApp?)
    case escape
}

enum NavigationEffect: Equatable {
    case none
    case requestCellRead
    case hidePreview
    case showPreview(CellContext)
}

enum WPSSelectionInput: Equatable {
    case mouseReleased
    case keyCode(UInt16)
    case keyReleased(UInt16)
}

enum WPSSelectionTriggerPolicy {
    private static let navigationKeyCodes: Set<UInt16> = [
        36,  // Return
        48,  // Tab
        76,  // Keypad Enter
        115, // Home
        116, // Page Up
        119, // End
        121, // Page Down
        123, // Left Arrow
        124, // Right Arrow
        125, // Down Arrow
        126, // Up Arrow
    ]

    static func shouldRequestClipboardRead(for input: WPSSelectionInput, app: SpreadsheetApp?) -> Bool {
        guard app == .wps else { return false }
        switch input {
        case .mouseReleased:
            return true
        case .keyCode:
            return false
        case let .keyReleased(keyCode):
            return isNavigationKey(keyCode)
        }
    }

    static func isNavigationKey(_ keyCode: UInt16) -> Bool {
        navigationKeyCodes.contains(keyCode)
    }
}

enum SpreadsheetSelectionTriggerPolicy {
    static func shouldRequestRead(for input: WPSSelectionInput, app: SpreadsheetApp?) -> Bool {
        guard app == .excel else { return false }
        switch input {
        case .mouseReleased:
            return true
        case .keyCode:
            return false
        case let .keyReleased(keyCode):
            return WPSSelectionTriggerPolicy.isNavigationKey(keyCode)
        }
    }
}

enum NavigationState: Equatable {
    case inactive
    case awaitingCellRead(app: SpreadsheetApp)
    case hidden(app: SpreadsheetApp)
    case visible(CellContext)
}

struct NavigationStateMachine {
    private(set) var state: NavigationState = .inactive

    mutating func handle(_ event: NavigationEvent) -> NavigationEffect {
        switch event {
        case let .cellSelectionChanged(app):
            state = .awaitingCellRead(app: app)
            return .requestCellRead

        case let .cellReadCompleted(context):
            guard case let .awaitingCellRead(app) = state else { return .none }
            guard let context,
                  context.app == app,
                  !context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .hidden(app: app)
                return .hidePreview
            }
            state = .visible(context)
            return .showPreview(context)

        case let .activeApplicationChanged(app):
            guard let app else {
                let shouldHide = state != .inactive
                state = .inactive
                return shouldHide ? .hidePreview : .none
            }

            switch state {
            case .inactive, .hidden:
                state = .awaitingCellRead(app: app)
                return .requestCellRead
            case let .awaitingCellRead(currentApp) where currentApp != app:
                state = .awaitingCellRead(app: app)
                return .requestCellRead
            case .awaitingCellRead, .visible:
                return .none
            }

        case .escape:
            guard case let .visible(context) = state else { return .none }
            state = .hidden(app: context.app)
            return .hidePreview
        }
    }
}
