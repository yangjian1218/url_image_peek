import AppKit
import Carbon

@main
final class ImagePeekApp: NSObject, NSApplicationDelegate {
    private static let appDelegate = ImagePeekApp()
    private let settingsStore = SettingsStore()
    private var operationsStatusStore: OperationsStatusStore?
    private var menuBarController: MenuBarController?
    private var previewRuntimeController: PreviewRuntimeController?

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.isRunningTests || Self.isOnlyRunningInstance else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        let operationsStatusStore = OperationsStatusStore()
        self.operationsStatusStore = operationsStatusStore
        menuBarController = MenuBarController(
            permissionManager: PermissionManager(),
            settingsStore: settingsStore,
            operationsStatusStore: operationsStatusStore,
            clearCache: { [weak self] in await self?.previewRuntimeController?.clearCache() ?? false }
        )
        previewRuntimeController = PreviewRuntimeController(
            settingsStore: settingsStore,
            operationsStatusStore: operationsStatusStore
        )
        previewRuntimeController?.start()
    }

    private static var isOnlyRunningInstance: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .isEmpty
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@MainActor
private final class PreviewRuntimeController {
    private struct LoadedImage {
        let image: NSImage
        let source: ImageLoadSource?
    }
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let wpsAdapter: WPSAdapter
    private let excelAdapter: ExcelAdapter
    private let webSheetAdapter: WebSheetAdapter
    private let panelController: PreviewPanelController
    private let globalSelectionPanelController: PreviewPanelController
    private let globalSelectedTextReader: GlobalSelectedTextReading
    private let remoteImageLoader: RemoteImageLoader
    private let settingsStore: SettingsStore
    private let operationsStatusStore: OperationsStatusStore
    private var diagnostics = RuntimeDiagnostics()

    private var pollTimer: Timer?
    private var selectionEventMonitor: Any?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var keyboardShortcutMonitor: RegisteredKeyboardShortcutMonitor?
    private var displayedContext: CellContext?
    private var displayedRequest: PreviewRequest?
    private var displayedImage: NSImage?
    private var dismissedContext: CellContext?
    private var pinnedPreview: (controller: PreviewPanelController, context: CellContext)?
    private var latestSelectionPoint: CGPoint?
    private var lastActiveApp: SpreadsheetApp?
    private var wpsClipboardReadTask: Task<Void, Never>?
    private var isReadingWPSClipboard = false
    private var hasPendingWPSClipboardRead = false
    private var readGeneration = 0
    private var displayGeneration = 0
    private var isReadingCurrentCell = false
    private var hasPendingCellRead = false
    private var globalSelectionPreviewTask: Task<Void, Never>?
    private var globalSelectionGeneration = 0
    private var globalSelectionPreviewBundleIdentifier: String?

    init(
        settingsStore: SettingsStore,
        activeApplicationDetector: ActiveApplicationDetecting = ActiveAppDetector(),
        wpsAdapter: WPSAdapter = WPSAdapter(),
        excelAdapter: ExcelAdapter = ExcelAdapter(),
        webSheetAdapter: WebSheetAdapter = WebSheetAdapter(),
        panelController: PreviewPanelController = PreviewPanelController(),
        globalSelectionPanelController: PreviewPanelController = PreviewPanelController(),
        globalSelectedTextReader: GlobalSelectedTextReading = SystemGlobalSelectedTextReader(),
        remoteImageLoader: RemoteImageLoader = RemoteImageLoader(),
        operationsStatusStore: OperationsStatusStore
    ) {
        self.activeApplicationDetector = activeApplicationDetector
        self.wpsAdapter = wpsAdapter
        self.excelAdapter = excelAdapter
        self.webSheetAdapter = webSheetAdapter
        self.panelController = panelController
        self.globalSelectionPanelController = globalSelectionPanelController
        self.globalSelectedTextReader = globalSelectedTextReader
        self.remoteImageLoader = remoteImageLoader
        self.settingsStore = settingsStore
        self.operationsStatusStore = operationsStatusStore
    }

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        selectionEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown, .leftMouseDragged, .mouseMoved, .keyUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSelectionEvent(event)
            }
        }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshKeyboardShortcutRegistration()
        }
        keyboardShortcutMonitor = RegisteredKeyboardShortcutMonitor { [weak self] shortcut in
            self?.handle(shortcut)
        }
        poll()
        refreshCacheSummary()
    }

    func clearCache() async -> Bool {
        let didClear = await remoteImageLoader.clearCache()
        refreshCacheSummary()
        return didClear
    }

    private func refreshCacheSummary() {
        Task { [weak self] in
            guard let self else { return }
            self.operationsStatusStore.updateCacheSummary(await self.remoteImageLoader.cacheSummary())
        }
    }

    private func poll() {
        refreshGlobalSelectionPreviewVisibility()
        refreshKeyboardShortcutRegistration()
        guard settingsStore.load().automaticPreview,
              let app = activeApplicationDetector.activeSpreadsheetApp() else {
            readGeneration &+= 1
            hasPendingCellRead = false
            lastActiveApp = nil
            dismissedContext = nil
            apply(.hide)
            return
        }

        let appChanged = lastActiveApp != app
        if appChanged {
            lastActiveApp = app
            if app == .wps { scheduleWPSClipboardRead() }
        }

        if appChanged || SpreadsheetPollingPolicy.shouldPollContinuously(app: app) {
            requestCurrentCellRead(for: app)
        }
    }

    private func requestCurrentCellRead(for app: SpreadsheetApp) {
        readGeneration &+= 1
        guard !isReadingCurrentCell else {
            hasPendingCellRead = true
            return
        }

        let generation = readGeneration
        isReadingCurrentCell = true
        Task { [weak self] in
            guard let self else { return }
            let context = await self.readCurrentCell(for: app)
            self.isReadingCurrentCell = false
            if app == .feishuChrome {
                self.operationsStatusStore.updateWebSheetReadStatus(self.webSheetAdapter.lastReadStatus)
            }

            if generation == self.readGeneration,
               self.activeApplicationDetector.activeSpreadsheetApp() == app,
               app != .wps || context != nil {
                self.apply(self.decision(for: context))
            }

            if self.hasPendingCellRead {
                self.hasPendingCellRead = false
                self.poll()
            }
        }
    }

    private func readCurrentCell(for app: SpreadsheetApp) async -> CellContext? {
        switch app {
        case .wps:
            return wpsAdapter.currentAccessibleCell()
        case .excel:
            return await excelAdapter.currentCell()
        case .feishuChrome:
            return await webSheetAdapter.currentCell()
        }
    }

    private func handleSelectionEvent(_ event: NSEvent) {
        handleGlobalSelectionEvent(event)

        let input: WPSSelectionInput
        switch event.type {
        case .leftMouseUp:
            input = .mouseReleased
            latestSelectionPoint = NSEvent.mouseLocation
        case .keyUp:
            input = .keyReleased(event.keyCode)
        default:
            return
        }

        let activeApp = activeApplicationDetector.activeSpreadsheetApp()
        if WPSSelectionTriggerPolicy.shouldRequestClipboardRead(for: input, app: activeApp) {
            dismissedContext = nil
            scheduleWPSClipboardRead()
        } else if SpreadsheetSelectionTriggerPolicy.shouldRequestRead(for: input, app: activeApp),
                  let activeApp {
            dismissedContext = nil
            requestCurrentCellRead(for: activeApp)
        }
    }

    private func handleGlobalSelectionEvent(_ event: NSEvent) {
        let globalEvent: GlobalSelectionPreviewEvent
        switch event.type {
        case .leftMouseUp:
            globalEvent = .mouseReleased
        case .leftMouseDown:
            globalEvent = .mousePressed
        case .leftMouseDragged:
            globalEvent = .pointerDragged
        case .mouseMoved:
            globalEvent = .pointerMoved
        case .keyUp:
            globalEvent = .keyReleased
        default:
            return
        }

        let settings = settingsStore.load()
        guard settings.globalSelectionPreviewEnabled,
              GlobalSelectionPreviewPolicy.shouldObserve(app: activeApplicationDetector.activeSpreadsheetApp()) else {
            cancelGlobalSelectionPreview(hide: true)
            return
        }

        if GlobalSelectionPreviewEventPolicy.shouldCancel(for: globalEvent) {
            cancelGlobalSelectionPreview(hide: true)
            return
        }

        guard GlobalSelectionPreviewEventPolicy.shouldSchedule(for: globalEvent),
              let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApplication.bundleIdentifier else {
            return
        }

        globalSelectionGeneration &+= 1
        let generation = globalSelectionGeneration
        let releasePoint = NSEvent.mouseLocation
        let frontmostApplicationName = frontmostApplication.localizedName ?? bundleIdentifier
        operationsStatusStore.updateGlobalSelectionReadStatus(.waiting)
        globalSelectionPreviewTask?.cancel()
        globalSelectionPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(GlobalSelectionPreviewCoordinator.delay * 1_000_000_000))
            guard let self else { return }
            guard !Task.isCancelled,
                  generation == self.globalSelectionGeneration,
                  self.settingsStore.load().globalSelectionPreviewEnabled,
                  GlobalSelectionPreviewPolicy.shouldObserve(app: self.activeApplicationDetector.activeSpreadsheetApp()) else {
                self.operationsStatusStore.updateGlobalSelectionReadStatus(.selectionChanged)
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else {
                let currentApplicationName = NSWorkspace.shared.frontmostApplication?.localizedName
                    ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    ?? "Unknown"
                self.operationsStatusStore.updateGlobalSelectionReadStatus(
                    .frontmostApplicationChanged(from: frontmostApplicationName, to: currentApplicationName)
                )
                return
            }

            let selection: GlobalSelectedTextSnapshot
            switch self.globalSelectedTextReader.selectedTextSnapshot() {
            case let .success(snapshot, diagnostics):
                self.operationsStatusStore.updateGlobalSelectionAccessibilityDiagnostics(diagnostics)
                selection = snapshot
            case let .failure(status, diagnostics):
                self.operationsStatusStore.updateGlobalSelectionAccessibilityDiagnostics(diagnostics)
                self.operationsStatusStore.updateGlobalSelectionReadStatus(status)
                return
            }

            guard selection.bundleIdentifier == bundleIdentifier else {
                self.operationsStatusStore.updateGlobalSelectionReadStatus(.selectionChanged)
                return
            }
            guard GlobalSelectionPreviewPolicy.isEligible(selectedText: selection.text),
                  let imageSource = ImageSourceResolver().resolve(selection.text) else {
                self.operationsStatusStore.updateGlobalSelectionReadStatus(.invalidImageURL)
                return
            }

            let request: PreviewRequest
            switch imageSource {
            case let .remote(url):
                request = .remote(url)
            case let .local(url):
                request = .local(url)
            }

            guard let loadedImage = await self.image(for: request),
                  generation == self.globalSelectionGeneration,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else {
                return
            }

            self.globalSelectionPreviewBundleIdentifier = bundleIdentifier
            let currentSettings = self.settingsStore.load()
            self.globalSelectionPanelController.show(
                image: loadedImage.image,
                cellFrame: nil,
                fallbackPoint: releasePoint,
                showsPixelDimensions: currentSettings.showsPixelDimensions,
                loadSource: currentSettings.showsLoadSource ? loadedImage.source : nil
            )
            self.operationsStatusStore.updateGlobalSelectionReadStatus(.ready)
        }
    }

    private func refreshGlobalSelectionPreviewVisibility() {
        guard settingsStore.load().globalSelectionPreviewEnabled,
              GlobalSelectionPreviewPolicy.shouldObserve(app: activeApplicationDetector.activeSpreadsheetApp()) else {
            cancelGlobalSelectionPreview(hide: true)
            return
        }

        if let globalSelectionPreviewBundleIdentifier,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != globalSelectionPreviewBundleIdentifier {
            cancelGlobalSelectionPreview(hide: true)
        }
    }

    private func cancelGlobalSelectionPreview(hide: Bool) {
        globalSelectionGeneration &+= 1
        globalSelectionPreviewTask?.cancel()
        globalSelectionPreviewTask = nil
        globalSelectionPreviewBundleIdentifier = nil
        if hide {
            globalSelectionPanelController.hide()
        }
    }

    private func scheduleWPSClipboardRead() {
        let settings = settingsStore.load()
        guard settings.automaticPreview, settings.wpsClipboardFallback else { return }
        hasPendingWPSClipboardRead = true
        guard !isReadingWPSClipboard else { return }

        wpsClipboardReadTask?.cancel()
        wpsClipboardReadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
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
            displayedRequest = nil
            displayedImage = nil
            displayGeneration &+= 1
            panelController.hide()
            refreshKeyboardShortcutRegistration()
            Task { await remoteImageLoader.cancelCurrentLoad() }

        case let .load(request, context):
            guard !PreviewDismissalPolicy.shouldSuppressLoad(context: context, dismissedContext: dismissedContext) else { return }
            dismissedContext = nil
            guard displayedContext != context else { return }
            displayedContext = context
            displayedRequest = request
            displayedImage = nil
            displayGeneration &+= 1
            let generation = displayGeneration
            Task { [weak self] in
                guard let self, let loadedImage = await self.image(for: request) else { return }
                guard generation == self.displayGeneration, self.displayedContext == context else { return }
                self.displayedImage = loadedImage.image
                self.refreshKeyboardShortcutRegistration()
                let settings = self.settingsStore.load()
                self.panelController.show(
                    image: loadedImage.image,
                    cellFrame: context.frame,
                    fallbackPoint: self.latestSelectionPoint ?? NSEvent.mouseLocation,
                    showsPixelDimensions: settings.showsPixelDimensions,
                    loadSource: settings.showsLoadSource ? loadedImage.source : nil
                )
            }
        }
    }

    deinit {
        if let selectionEventMonitor {
            NSEvent.removeMonitor(selectionEventMonitor)
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        keyboardShortcutMonitor?.stop()
        globalSelectionPreviewTask?.cancel()
    }

    private func refreshKeyboardShortcutRegistration() {
        keyboardShortcutMonitor?.update(
            app: activeApplicationDetector.activeSpreadsheetApp(),
            hasPreview: displayedImage != nil
        )
    }

    private func handle(_ shortcut: PreviewShortcut) {
        guard PreviewShortcutPolicy.canHandle(
            shortcut,
            app: activeApplicationDetector.activeSpreadsheetApp(),
            hasPreview: displayedImage != nil
        ) else { return }

        switch shortcut {
        case .escape:
            dismissedContext = displayedContext
            apply(.hide)
        case .space:
            panelController.toggleExpandedPreview()
        case .optionC:
            copyPreviewImage()
        case .optionO:
            openPreviewSource()
        case .optionR:
            revealLocalPreviewSource()
        case .optionP:
            togglePinnedPreview()
        case .letter:
            break
        }
    }

    private func copyPreviewImage() {
        guard let image = displayedImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func openPreviewSource() {
        guard let displayedRequest else { return }
        let url: URL
        switch displayedRequest {
        case let .remote(remoteURL), let .local(remoteURL):
            url = remoteURL
        }
        NSWorkspace.shared.open(url)
    }

    private func revealLocalPreviewSource() {
        guard case let .local(url) = displayedRequest else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func togglePinnedPreview() {
        guard let image = displayedImage, let context = displayedContext else { return }
        if pinnedPreview?.context == context {
            pinnedPreview?.controller.hide()
            pinnedPreview = nil
            return
        }

        pinnedPreview?.controller.hide()
        let controller = PreviewPanelController()
        controller.showPinned(image: image)
        pinnedPreview = (controller, context)
    }

    private func image(for request: PreviewRequest) async -> LoadedImage? {
        let startedAt = Date()
        switch request {
        case let .local(url):
            let image = NSImage(contentsOf: url)
            recordDiagnostic(image == nil ? .failure : .localSuccess)
            return image.map { LoadedImage(image: $0, source: nil) }
        case let .remote(url):
            do {
                guard let result = try await remoteImageLoader.loadData(from: url) else {
                    recordDiagnostic(.cancelled)
                    return nil
                }
                guard let image = NSImage(data: result.data) else {
                    recordDiagnostic(.failure)
                    return nil
                }
                recordDiagnostic(.success(source: result.source, elapsed: Date().timeIntervalSince(startedAt)))
                return LoadedImage(image: image, source: result.source)
            } catch {
                recordDiagnostic(.failure)
                return nil
            }
        }
    }

    private func recordDiagnostic(_ result: RuntimeDiagnosticResult) {
        diagnostics.record(result)
        operationsStatusStore.updateDiagnostics(diagnostics.snapshot)
    }
}

private final class RegisteredKeyboardShortcutMonitor {
    private static let signature = OSType(0x494D504B) // "IMPK"
    private static let eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    private let handle: (PreviewShortcut) -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var isRegistered = false

    init(handle: @escaping (PreviewShortcut) -> Void) {
        self.handle = handle
        var eventType = Self.eventType
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func update(app: SpreadsheetApp?, hasPreview: Bool) {
        let shouldRegister = PreviewShortcutPolicy.canHandle(.space, app: app, hasPreview: hasPreview)
        guard shouldRegister != isRegistered else { return }
        if shouldRegister {
            registerHotKeys()
        } else {
            unregisterHotKeys()
        }
    }

    func stop() {
        unregisterHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        stop()
    }

    private func registerHotKeys() {
        let definitions: [(PreviewShortcut, UInt32, UInt32)] = [
            (.space, 49, 0),
            (.escape, 53, 0),
            (.optionC, 8, UInt32(optionKey)),
            (.optionO, 31, UInt32(optionKey)),
            (.optionR, 15, UInt32(optionKey)),
            (.optionP, 35, UInt32(optionKey)),
        ]
        var registeredHotKeys: [EventHotKeyRef] = []
        for (index, definition) in definitions.enumerated() {
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            guard RegisterEventHotKey(
                definition.1,
                definition.2,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            ) == noErr, let hotKey else {
                registeredHotKeys.forEach { _ = UnregisterEventHotKey($0) }
                return
            }
            registeredHotKeys.append(hotKey)
        }
        hotKeys = registeredHotKeys
        isRegistered = true
    }

    private func unregisterHotKeys() {
        hotKeys.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        isRegistered = false
    }

    private static let callback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        var identifier = EventHotKeyID()
        guard GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        ) == noErr,
        identifier.signature == RegisteredKeyboardShortcutMonitor.signature,
        let shortcut = RegisteredKeyboardShortcutMonitor.shortcut(for: identifier.id) else {
            return noErr
        }

        let monitor = Unmanaged<RegisteredKeyboardShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
            monitor.handle(shortcut)
        }
        return noErr
    }

    private static func shortcut(for identifier: UInt32) -> PreviewShortcut? {
        switch identifier {
        case 1: .space
        case 2: .escape
        case 3: .optionC
        case 4: .optionO
        case 5: .optionR
        case 6: .optionP
        default: nil
        }
    }
}
