import AppKit

@main
final class ImagePeekApp: NSObject, NSApplicationDelegate {
    private static let appDelegate = ImagePeekApp()
    private var menuBarController: MenuBarController?
    private var previewRuntimeController: PreviewRuntimeController?

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(permissionManager: PermissionManager())
        previewRuntimeController = PreviewRuntimeController(settings: SettingsStore().load())
        previewRuntimeController?.start()
    }
}

@MainActor
private final class PreviewRuntimeController {
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let wpsAdapter: WPSAdapter
    private let excelAdapter: ExcelAdapter
    private let coordinator: PreviewRuntimeCoordinator
    private let panelController: PreviewPanelController
    private let remoteImageLoader: RemoteImageLoader
    private let automaticPreview: Bool

    private var pollTimer: Timer?
    private var displayedContext: CellContext?
    private var readGeneration = 0
    private var displayGeneration = 0

    init(
        settings: ImagePeekSettings,
        activeApplicationDetector: ActiveApplicationDetecting = ActiveAppDetector(),
        wpsAdapter: WPSAdapter = WPSAdapter(),
        excelAdapter: ExcelAdapter = ExcelAdapter(),
        panelController: PreviewPanelController = PreviewPanelController(),
        remoteImageLoader: RemoteImageLoader = RemoteImageLoader()
    ) {
        self.activeApplicationDetector = activeApplicationDetector
        self.wpsAdapter = wpsAdapter
        self.excelAdapter = excelAdapter
        self.coordinator = PreviewRuntimeCoordinator(
            imageColumnFilter: ImageColumnFilter(column: settings.imageColumn)
        )
        self.panelController = panelController
        self.remoteImageLoader = remoteImageLoader
        self.automaticPreview = settings.automaticPreview
    }

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func poll() {
        guard automaticPreview, let app = activeApplicationDetector.activeSpreadsheetApp() else {
            apply(.hide)
            return
        }

        readGeneration &+= 1
        let generation = readGeneration
        Task { [weak self] in
            guard let self else { return }
            let context = await self.readCurrentCell(for: app)
            guard generation == self.readGeneration else { return }
            self.apply(self.coordinator.decision(for: context))
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
                    fallbackPoint: NSEvent.mouseLocation
                )
            }
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
