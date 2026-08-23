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

enum PreviewImageLayout {
    static func displaySize(imageSize: CGSize, availableSize: CGSize, zoom: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return availableSize }
        let fitScale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let scale = fitScale * PreviewZoom.clamped(zoom)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
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
        guard hasPreview, let app, app == .wps || app == .excel else { return false }
        switch shortcut {
        case .escape, .space, .optionC, .optionO, .optionR, .optionP:
            return true
        case .letter:
            return false
        }
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
    private let scrollView = NSScrollView()
    private let imageView = ZoomableImageView()
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

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.onZoom = { [weak self] scale in self?.applyZoom(scale) }
        scrollView.documentView = imageView
        panel.contentView = scrollView
    }

    func show(image: NSImage, cellFrame: CGRect?, fallbackPoint: CGPoint?, screen: NSScreen? = NSScreen.main) {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        isExpanded = false
        lastCellFrame = cellFrame
        lastFallbackPoint = fallbackPoint
        panelSize = PreviewPanelLayout.contentSize(for: image.size)
        imageView.image = image
        panel.setContentSize(panelSize)
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

    func toggleExpandedPreview(screen: NSScreen? = NSScreen.main) {
        guard let image = imageView.image else { return }
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        isExpanded.toggle()
        panelSize = isExpanded
            ? PreviewPanelLayout.expandedContentSize(for: image.size, visibleFrame: visibleFrame)
            : PreviewPanelLayout.contentSize(for: image.size)
        panel.setContentSize(panelSize)
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
}

private final class ZoomableImageView: NSImageView {
    var zoomScale: CGFloat = 1
    var onZoom: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        onZoom?(PreviewZoom.clamped(zoomScale + event.scrollingDeltaY * 0.01))
    }
}
