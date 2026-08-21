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
