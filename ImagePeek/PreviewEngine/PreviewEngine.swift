import AppKit

enum PreviewEngine {}

enum PreviewLayout {
    static func frame(
        cellFrame: CGRect?,
        fallbackPoint: CGPoint?,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGRect {
        let origin: CGPoint
        if let cellFrame {
            let rightOrigin = CGPoint(x: cellFrame.maxX + gap, y: cellFrame.midY - panelSize.height / 2)
            let leftOrigin = CGPoint(x: cellFrame.minX - gap - panelSize.width, y: rightOrigin.y)
            origin = rightOrigin.x + panelSize.width <= visibleFrame.maxX ? rightOrigin : leftOrigin
        } else if let fallbackPoint {
            let rightOrigin = CGPoint(x: fallbackPoint.x + gap, y: fallbackPoint.y - panelSize.height / 2)
            let leftOrigin = CGPoint(x: fallbackPoint.x - gap - panelSize.width, y: rightOrigin.y)
            origin = rightOrigin.x + panelSize.width <= visibleFrame.maxX ? rightOrigin : leftOrigin
        } else {
            origin = CGPoint(x: visibleFrame.midX - panelSize.width / 2, y: visibleFrame.midY - panelSize.height / 2)
        }

        return CGRect(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panelSize.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panelSize.height),
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

enum PinnedPreviewLayout {
    static let screenInset: CGFloat = 24

    static func frame(
        panelSize: CGSize,
        visibleFrame: CGRect,
        inset: CGFloat = screenInset
    ) -> CGRect {
        CGRect(
            x: visibleFrame.maxX - panelSize.width - inset,
            y: visibleFrame.maxY - panelSize.height - inset,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

enum PreviewPanelLayout {
    static let maximumSize = CGSize(width: 360, height: 480)
    static let defaultSize = CGSize(width: 320, height: 260)

    static func contentSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return defaultSize }
        let scale = min(maximumSize.width / imageSize.width, maximumSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func expandedContentSize(for imageSize: CGSize, visibleFrame: CGRect) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return defaultSize }
        let maximumSize = CGSize(
            width: max(1, visibleFrame.width - 48),
            height: max(1, visibleFrame.height - 48)
        )
        let scale = min(maximumSize.width / imageSize.width, maximumSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

enum PreviewZoom {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 5

    static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimum), maximum)
    }
}

enum PreviewScrollPolicy {
    static func showsScrollers(for zoom: CGFloat) -> Bool {
        PreviewZoom.clamped(zoom) > 1
    }
}

enum PreviewPan {
    static func clampedOrigin(
        _ origin: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, 0), max(0, contentSize.width - viewportSize.width)),
            y: min(max(origin.y, 0), max(0, contentSize.height - viewportSize.height))
        )
    }

    static func originAfterDrag(
        currentOrigin: CGPoint,
        dragDelta: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        clampedOrigin(
            CGPoint(x: currentOrigin.x - dragDelta.x, y: currentOrigin.y - dragDelta.y),
            contentSize: contentSize,
            viewportSize: viewportSize
        )
    }
}

enum PreviewImageLayout {
    static func displaySize(imageSize: CGSize, availableSize: CGSize, zoom: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return availableSize }
        let fitScale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let scale = fitScale * PreviewZoom.clamped(zoom)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

enum PreviewImageInfo {
    static let captionBottomInset: CGFloat = 20
    static let captionBackgroundOpacity: CGFloat = 0.42

    static func pixelSizeText(for size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
    }

    static func captionFrame(containerSize: CGSize) -> CGRect {
        CGRect(
            x: 8,
            y: captionBottomInset,
            width: max(0, containerSize.width - 16),
            height: 20
        )
    }

    static func captionText(
        pixelSize: CGSize,
        source: ImageLoadSource?,
        showsPixelDimensions: Bool,
        showsLoadSource: Bool
    ) -> String? {
        let sourceText: String?
        switch source {
        case .network:
            sourceText = "Network"
        case .diskCache:
            sourceText = "Disk cache"
        case .memoryCache:
            sourceText = "Memory cache"
        case nil:
            sourceText = nil
        }
        let parts = [
            showsPixelDimensions ? pixelSizeText(for: pixelSize) : nil,
            showsLoadSource ? sourceText : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum PreviewDismissalPolicy {
    static func shouldSuppressLoad(context: CellContext, dismissedContext: CellContext?) -> Bool {
        context == dismissedContext
    }
}

enum PreviewShortcut: Equatable {
    case escape
    case space
    case optionC
    case optionO
    case optionR
    case optionP
    case letter(String)
}

enum PreviewShortcutPolicy {
    static func canHandle(_ shortcut: PreviewShortcut, app: SpreadsheetApp?, hasPreview: Bool) -> Bool {
        guard hasPreview, let app, app == .wps || app == .excel || app == .feishuChrome else { return false }
        switch shortcut {
        case .escape, .space, .optionC, .optionO, .optionR, .optionP:
            return true
        case .letter:
            return false
        }
    }
}

enum KeyboardShortcutEventTapPolicy {
    enum StartAction: Equatable {
        case start
        case requestAccessibility
    }

    static func canStart(accessibilityGranted: Bool) -> Bool {
        accessibilityGranted
    }

    static func startAction(accessibilityGranted: Bool) -> StartAction {
        accessibilityGranted ? .start : .requestAccessibility
    }
}

enum PreviewShortcutResolver {
    static func shortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> PreviewShortcut? {
        let significantModifiers = modifiers.intersection([.command, .control, .option, .function])
        if significantModifiers.contains(.option) {
            switch keyCode {
            case 8: return .optionC
            case 31: return .optionO
            case 15: return .optionR
            case 35: return .optionP
            default: return nil
            }
        }

        guard significantModifiers.isEmpty else { return nil }
        switch keyCode {
        case 49: return .space
        case 53: return .escape
        default: return nil
        }
    }
}

final class PreviewPanelController {
    private let panel: NSPanel
    private let contentView = NSView()
    private let scrollView = NSScrollView()
    private let imageView = ZoomableImageView()
    private let imageInfoLabel = NSTextField(labelWithString: "")
    private var panelSize = PreviewPanelLayout.defaultSize
    private var isExpanded = false
    private var lastCellFrame: CGRect?
    private var lastFallbackPoint: CGPoint?

    init() {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.onZoom = { [weak self] scale in self?.applyZoom(scale) }
        imageView.onPan = { [weak self] delta in self?.panImage(by: delta) }
        scrollView.documentView = imageView

        imageInfoLabel.alignment = .center
        imageInfoLabel.textColor = .white
        imageInfoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        imageInfoLabel.wantsLayer = true
        imageInfoLabel.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(PreviewImageInfo.captionBackgroundOpacity)
            .cgColor
        imageInfoLabel.layer?.cornerRadius = 4
        imageInfoLabel.frame = PreviewImageInfo.captionFrame(containerSize: panelSize)

        contentView.addSubview(scrollView)
        contentView.addSubview(imageInfoLabel)
        panel.contentView = contentView
    }

    func show(
        image: NSImage,
        cellFrame: CGRect?,
        fallbackPoint: CGPoint?,
        showsPixelDimensions: Bool = true,
        loadSource: ImageLoadSource? = nil,
        screen: NSScreen? = NSScreen.main
    ) {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        isExpanded = false
        lastCellFrame = cellFrame
        lastFallbackPoint = fallbackPoint
        panelSize = PreviewPanelLayout.contentSize(for: image.size)
        imageView.image = image
        updateCaption(
            image: image,
            source: loadSource,
            showsPixelDimensions: showsPixelDimensions,
            showsLoadSource: loadSource != nil
        )
        panel.setContentSize(panelSize)
        layoutContent()
        panel.setFrame(
            PreviewLayout.frame(
                cellFrame: cellFrame,
                fallbackPoint: fallbackPoint,
                panelSize: panelSize,
                visibleFrame: visibleFrame
            ),
            display: true
        )
        applyZoom(1)
        panel.orderFrontRegardless()
    }

    func showPinned(image: NSImage, screen: NSScreen? = nil) {
        let targetScreen = screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        isExpanded = false
        lastCellFrame = nil
        lastFallbackPoint = nil
        panelSize = PreviewPanelLayout.contentSize(for: image.size)
        imageView.image = image
        updateCaption(image: image, source: nil, showsPixelDimensions: true, showsLoadSource: false)
        panel.setContentSize(panelSize)
        layoutContent()
        panel.setFrame(
            PinnedPreviewLayout.frame(panelSize: panelSize, visibleFrame: visibleFrame),
            display: true
        )
        applyZoom(1)
        panel.orderFrontRegardless()
    }

    func toggleExpandedPreview(screen: NSScreen? = NSScreen.main) {
        guard let image = imageView.image else { return }
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        isExpanded.toggle()
        panelSize = isExpanded
            ? PreviewPanelLayout.expandedContentSize(for: image.size, visibleFrame: visibleFrame)
            : PreviewPanelLayout.contentSize(for: image.size)
        panel.setContentSize(panelSize)
        layoutContent()
        panel.setFrame(
            PreviewLayout.frame(
                cellFrame: lastCellFrame,
                fallbackPoint: lastFallbackPoint,
                panelSize: panelSize,
                visibleFrame: visibleFrame
            ),
            display: true
        )
        applyZoom(1)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func applyZoom(_ scale: CGFloat) {
        imageView.zoomScale = PreviewZoom.clamped(scale)
        let showsScrollers = PreviewScrollPolicy.showsScrollers(for: imageView.zoomScale)
        scrollView.hasVerticalScroller = showsScrollers
        scrollView.hasHorizontalScroller = showsScrollers
        let imageSize = imageView.image?.size ?? panelSize
        imageView.frame = CGRect(
            origin: .zero,
            size: PreviewImageLayout.displaySize(
                imageSize: imageSize,
                availableSize: panelSize,
                zoom: imageView.zoomScale
            )
        )
    }

    private func panImage(by delta: CGPoint) {
        guard imageView.zoomScale > 1 else { return }
        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let targetOrigin = PreviewPan.originAfterDrag(
            currentOrigin: currentOrigin,
            dragDelta: delta,
            contentSize: imageView.bounds.size,
            viewportSize: clipView.bounds.size
        )
        clipView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        if let representation = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           representation.pixelsWide > 0,
           representation.pixelsHigh > 0 {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return image.size
    }

    private func layoutContent() {
        scrollView.frame = contentView.bounds
        imageInfoLabel.frame = PreviewImageInfo.captionFrame(containerSize: contentView.bounds.size)
    }

    private func updateCaption(
        image: NSImage,
        source: ImageLoadSource?,
        showsPixelDimensions: Bool,
        showsLoadSource: Bool
    ) {
        let caption = PreviewImageInfo.captionText(
            pixelSize: pixelSize(of: image),
            source: source,
            showsPixelDimensions: showsPixelDimensions,
            showsLoadSource: showsLoadSource
        )
        imageInfoLabel.stringValue = caption ?? ""
        imageInfoLabel.isHidden = caption == nil
    }
}

private final class ZoomableImageView: NSImageView {
    var zoomScale: CGFloat = 1
    var onZoom: ((CGFloat) -> Void)?
    var onPan: ((CGPoint) -> Void)?
    private var lastDragPointInWindow: CGPoint?

    override func mouseDown(with event: NSEvent) {
        guard zoomScale > 1 else {
            super.mouseDown(with: event)
            return
        }
        lastDragPointInWindow = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoomScale > 1,
              let lastDragPointInWindow else { return }
        let currentPointInWindow = event.locationInWindow
        onPan?(CGPoint(
            x: currentPointInWindow.x - lastDragPointInWindow.x,
            y: currentPointInWindow.y - lastDragPointInWindow.y
        ))
        self.lastDragPointInWindow = currentPointInWindow
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPointInWindow = nil
        guard zoomScale <= 1 else { return }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        onZoom?(PreviewZoom.clamped(zoomScale + event.scrollingDeltaY * 0.01))
    }
}
