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
            origin = CGPoint(x: fallbackPoint.x + gap, y: fallbackPoint.y - panelSize.height / 2)
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

enum PreviewZoom {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 5

    static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimum), maximum)
    }
}

enum PreviewShortcut: Equatable {
    case escape
    case space
    case optionC
    case optionR
    case optionP
    case letter(String)
}

enum PreviewShortcutPolicy {
    static func canHandle(_ shortcut: PreviewShortcut, app: SpreadsheetApp?, hasPreview: Bool) -> Bool {
        guard hasPreview, app == .wps || hasPreview, app == .excel else { return false }
        switch shortcut {
        case .escape, .space, .optionC, .optionR, .optionP:
            return true
        case .letter:
            return false
        }
    }
}

final class PreviewPanelController {
    private let panel: NSPanel
    private let scrollView = NSScrollView()
    private let imageView = ZoomableImageView()
    private let panelSize = CGSize(width: 320, height: 260)

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
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.onZoom = { [weak self] scale in self?.applyZoom(scale) }
        scrollView.documentView = imageView
        panel.contentView = scrollView
    }

    func show(image: NSImage, cellFrame: CGRect?, fallbackPoint: CGPoint?, screen: NSScreen? = NSScreen.main) {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        panel.setFrame(
            PreviewLayout.frame(
                cellFrame: cellFrame,
                fallbackPoint: fallbackPoint,
                panelSize: panelSize,
                visibleFrame: visibleFrame
            ),
            display: true
        )
        imageView.image = image
        applyZoom(1)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func applyZoom(_ scale: CGFloat) {
        imageView.zoomScale = PreviewZoom.clamped(scale)
        let imageSize = imageView.image?.size ?? panelSize
        imageView.frame = CGRect(origin: .zero, size: CGSize(width: imageSize.width * imageView.zoomScale, height: imageSize.height * imageView.zoomScale))
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
