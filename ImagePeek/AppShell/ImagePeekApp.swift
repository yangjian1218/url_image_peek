import AppKit

@main
final class ImagePeekApp: NSObject, NSApplicationDelegate {
    private static let appDelegate = ImagePeekApp()
    private let settingsStore = SettingsStore()
    private var menuBarController: MenuBarController?
    private var previewRuntimeController: PreviewRuntimeController?

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(
            permissionManager: PermissionManager(),
            settingsStore: settingsStore
        )
        previewRuntimeController = PreviewRuntimeController(settingsStore: settingsStore)
        previewRuntimeController?.start()
    }
}

@MainActor
private final class PreviewRuntimeController {
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let wpsAdapter: WPSAdapter
    private let excelAdapter: ExcelAdapter
    private let panelController: PreviewPanelController
    private let remoteImageLoader: RemoteImageLoader
    private let settingsStore: SettingsStore

    private var pollTimer: Timer?
    private var selectionEventMonitor: Any?
    private var displayedContext: CellContext?
    private var latestSelectionPoint: CGPoint?
    private var lastActiveApp: SpreadsheetApp?
    private var wpsClipboardReadTask: Task<Void, Never>?
    private var isReadingWPSClipboard = false
    private var hasPendingWPSClipboardRead = false
    private var readGeneration = 0
    private var displayGeneration = 0

    init(
        settingsStore: SettingsStore,
        activeApplicationDetector: ActiveApplicationDetecting = ActiveAppDetector(),
        wpsAdapter: WPSAdapter = WPSAdapter(),
        excelAdapter: ExcelAdapter = ExcelAdapter(),
        panelController: PreviewPanelController = PreviewPanelController(),
        remoteImageLoader: RemoteImageLoader = RemoteImageLoader()
    ) {
        self.activeApplicationDetector = activeApplicationDetector
        self.wpsAdapter = wpsAdapter
        self.excelAdapter = excelAdapter
        self.panelController = panelController
        self.remoteImageLoader = remoteImageLoader
        self.settingsStore = settingsStore
    }

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        selectionEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSelectionEvent(event)
            }
        }
        poll()
    }

    private func poll() {
        guard settingsStore.load().automaticPreview,
              let app = activeApplicationDetector.activeSpreadsheetApp() else {
            lastActiveApp = nil
            apply(.hide)
            return
        }

        if lastActiveApp != app {
            lastActiveApp = app
            if app == .wps { scheduleWPSClipboardRead() }
        }

        readGeneration &+= 1
        let generation = readGeneration
        Task { [weak self] in
            guard let self else { return }
            let context = await self.readCurrentCell(for: app)
            guard generation == self.readGeneration else { return }
            guard app != .wps || context != nil else { return }
            self.apply(self.decision(for: context))
        }
    }

    private func readCurrentCell(for app: SpreadsheetApp) async -> CellContext? {
        switch app {
        case .wps:
            return wpsAdapter.currentAccessibleCell()
        case .excel:
            return await excelAdapter.currentCell()
        }
    }

    private func handleSelectionEvent(_ event: NSEvent) {
        let input: WPSSelectionInput
        switch event.type {
        case .leftMouseUp:
            input = .mouseReleased
            latestSelectionPoint = NSEvent.mouseLocation
        case .keyDown:
            input = .keyCode(event.keyCode)
        default:
            return
        }

        guard WPSSelectionTriggerPolicy.shouldRequestClipboardRead(
            for: input,
            app: activeApplicationDetector.activeSpreadsheetApp()
        ) else { return }
        scheduleWPSClipboardRead()
    }

    private func scheduleWPSClipboardRead() {
        let settings = settingsStore.load()
        guard settings.automaticPreview, settings.wpsClipboardFallback else { return }
        hasPendingWPSClipboardRead = true
        guard !isReadingWPSClipboard else { return }

        wpsClipboardReadTask?.cancel()
        wpsClipboardReadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await self?.readWPSClipboardAfterSelection()
        }
    }

    private func readWPSClipboardAfterSelection() async {
        guard hasPendingWPSClipboardRead,
              !isReadingWPSClipboard,
              activeApplicationDetector.activeSpreadsheetApp() == .wps else { return }
        hasPendingWPSClipboardRead = false
        isReadingWPSClipboard = true
        let context = await wpsAdapter.currentCell()
        isReadingWPSClipboard = false
        wpsClipboardReadTask = nil

        guard activeApplicationDetector.activeSpreadsheetApp() == .wps else { return }
        apply(decision(for: context))

        if hasPendingWPSClipboardRead {
            scheduleWPSClipboardRead()
        }
    }

    private func decision(for context: CellContext?) -> PreviewRuntimeDecision {
        PreviewRuntimeCoordinator(
            imageColumnFilter: ImageColumnFilter(column: settingsStore.load().imageColumn)
        ).decision(for: context)
    }

    private func apply(_ decision: PreviewRuntimeDecision) {
        switch decision {
        case .hide:
            guard displayedContext != nil else { return }
            displayedContext = nil
            displayGeneration &+= 1
            panelController.hide()
            Task { await remoteImageLoader.cancelCurrentLoad() }

        case let .load(request, context):
            guard displayedContext != context else { return }
            displayedContext = context
            displayGeneration &+= 1
            let generation = displayGeneration
            Task { [weak self] in
                guard let self, let image = await self.image(for: request) else { return }
                guard generation == self.displayGeneration, self.displayedContext == context else { return }
                self.panelController.show(
                    image: image,
                    cellFrame: context.frame,
                    fallbackPoint: self.latestSelectionPoint ?? NSEvent.mouseLocation
                )
            }
        }
    }

    deinit {
        if let selectionEventMonitor {
            NSEvent.removeMonitor(selectionEventMonitor)
        }
    }

    private func image(for request: PreviewRequest) async -> NSImage? {
        switch request {
        case let .local(url):
            return NSImage(contentsOf: url)
        case let .remote(url):
            do {
                guard let result = try await remoteImageLoader.loadData(from: url) else { return nil }
                return NSImage(data: result.data)
            } catch {
                return nil
            }
        }
    }
}
