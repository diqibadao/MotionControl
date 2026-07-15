import AppKit
import CoreGraphics

/// 调试蒙层：透明窗口覆盖全屏，显示 AX 扫描到的可交互元素位置
/// 测试模式下启用，正常使用时可关闭
class DebugOverlay {
    private let window: NSWindow
    private let overlayView: OverlayView
    private var refreshTimer: Timer?

    init() {
        let screen = NSScreen.main?.frame ?? .zero
        window = NSWindow(
            contentRect: screen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false

        overlayView = OverlayView(frame: screen)
        window.contentView = overlayView
    }

    func start() {
        window.orderFront(nil)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.overlayView.needsDisplay = true
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        window.orderOut(nil)
    }

    func update(elements: [UIElementInfo], cursor: CGPoint, nearestCenter: CGPoint?) {
        overlayView.elements = elements
        overlayView.cursor = cursor
        overlayView.nearestCenter = nearestCenter
    }
}

private class OverlayView: NSView {
    var elements: [UIElementInfo] = []
    var cursor: CGPoint = .zero
    var nearestCenter: CGPoint?

    override func draw(_ rect: CGRect) {
        guard !elements.isEmpty else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Y轴翻转：AX坐标 → 屏幕坐标
        let screenH = bounds.height

        for el in elements {
            let axFrame = el.frame
            let rect = CGRect(
                x: axFrame.origin.x,
                y: screenH - axFrame.origin.y - axFrame.height,
                width: axFrame.width,
                height: axFrame.height
            )

            guard rect.width > 0, rect.height > 0 else { continue }

            // 所有元素：半透明青绿色框 + 中心小点
            ctx.setStrokeColor(CGColor(red: 0, green: 1, blue: 0.6, alpha: 0.3))
            ctx.setLineWidth(1)
            ctx.stroke(rect)

            let cx = rect.midX
            let cy = rect.midY
            ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0.6, alpha: 0.4))
            ctx.fillEllipse(in: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4))
        }

        // 最近目标：亮黄色高亮 + 中心大点 + 连线
        if let nc = nearestCenter {
            ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 0.7))
            ctx.fillEllipse(in: CGRect(x: nc.x - 6, y: nc.y - 6, width: 12, height: 12))

            // 光标到目标的连线
            ctx.setStrokeColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 0.4))
            ctx.setLineWidth(1)
            ctx.move(to: cursor)
            ctx.addLine(to: nc)
            ctx.strokePath()
        }

        // 光标位置：红点
        ctx.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: cursor.x - 4, y: cursor.y - 4, width: 8, height: 8))
    }
}
