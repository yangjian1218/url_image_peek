import AppKit
import ApplicationServices

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
    private var keyboardShortcutMonitor: KeyboardShortcutMonitor?
    private var displayedContext: CellContext?
    private var displayedRequest: PreviewRequest?
    private var displayedImage: NSImage?
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
        selectionEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSelectionEvent(event)
            }
        }
        keyboardShortcutMonitor = KeyboardShortcutMonitor(
            shouldHandle: { [weak self] shortcut in
                guard let self else { return false }
                return PreviewShortcutPolicy.canHandle(
                    shortcut,
                    app: self.activeApplicationDetector.activeSpreadsheetApp(),
                    hasPreview: self.displayedImage != nil
                )
            },
            handle: { [weak self] shortcut in
                self?.handle(shortcut)
            }
        )
        keyboardShortcutMonitor?.start()
        poll()
    }

    private func poll() {
        guard settingsStore.load().automaticPreview,
              let app = activeApplicationDetector.activeSpreadsheetApp() else {
            readGeneration &+= 1
            hasPendingCellRead = false
            lastActiveApp = nil
            apply(.hide)
            return
        }

        if lastActiveApp != app {
            lastActiveApp = app
            if app == .wps { scheduleWPSClipboardRead() }
        }

        requestCurrentCellRead(for: app)
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
        }
    }

    private func handleSelectionEvent(_ event: NSEvent) {
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
            scheduleWPSClipboardRead()
        } else if SpreadsheetSelectionTriggerPolicy.shouldRequestRead(for: input, app: activeApp),
                  let activeApp {
            requestCurrentCellRead(for: activeApp)
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
            Task { await remoteImageLoader.cancelCurrentLoad() }

        case let .load(request, context):
            guard displayedContext != context else { return }
            displayedContext = context
            displayedRequest = request
            displayedImage = nil
            displayGeneration &+= 1
            let generation = displayGeneration
            Task { [weak self] in
                guard let self, let image = await self.image(for: request) else { return }
                guard generation == self.displayGeneration, self.displayedContext == context else { return }
                self.displayedImage = image
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

    private func handle(_ shortcut: PreviewShortcut) {
        guard PreviewShortcutPolicy.canHandle(
            shortcut,
            app: activeApplicationDetector.activeSpreadsheetApp(),
            hasPreview: displayedImage != nil
        ) else { return }

        switch shortcut {
        case .escape:
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

private final class KeyboardShortcutMonitor {
    private let shouldHandle: (PreviewShortcut) -> Bool
    private let handle: (PreviewShortcut) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        shouldHandle: @escaping (PreviewShortcut) -> Bool,
        handle: @escaping (PreviewShortcut) -> Void
    ) {
        self.shouldHandle = shouldHandle
        self.handle = handle
    }

    func start() {
        guard eventTap == nil else { return }
        let accessibilityGranted = AXIsProcessTrusted()
        guard KeyboardShortcutEventTapPolicy.startAction(accessibilityGranted: accessibilityGranted) == .start else {
            Self.requestAccessibilityPrompt()
            return
        }
        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let reference = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.callback,
            userInfo: reference
        ) else {
            return
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput,
           let eventTap = monitor.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              let shortcut = PreviewShortcutResolver.shortcut(
                  keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                  modifiers: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
              ),
              monitor.shouldHandle(shortcut) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            monitor.handle(shortcut)
        }
        return nil
    }

    private static func requestAccessibilityPrompt() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
