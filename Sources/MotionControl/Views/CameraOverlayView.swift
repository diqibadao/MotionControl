import AppKit
import SwiftUI

// MARK: - SwiftUI wrapper (NSViewRepresentable)
struct CameraOverlayView: NSViewRepresentable {
    var handKeypoints: [CGPoint] = []
    var faceKeypoints: [CGPoint] = []
    var isCommandActive: Bool = false

    func makeNSView(context: Context) -> OverlayNSView {
        let view = OverlayNSView()
        view.handKeypoints = handKeypoints
        view.faceKeypoints = faceKeypoints
        view.isCommandActive = isCommandActive
        return view
    }

    func updateNSView(_ nsView: OverlayNSView, context: Context) {
        nsView.handKeypoints = handKeypoints
        nsView.faceKeypoints = faceKeypoints
        nsView.isCommandActive = isCommandActive
        nsView.needsDisplay = true
    }
}

// MARK: - Custom NSView that performs the drawing
class OverlayNSView: NSView {
    var handKeypoints: [CGPoint] = []
    var faceKeypoints: [CGPoint] = []
    var isCommandActive: Bool = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let w = bounds.width
        let h = bounds.height

        // --- 绘制面部特征点 (半径2pt) ---
        if !faceKeypoints.isEmpty {
            ctx.setShouldAntialias(true)
            if isCommandActive {
                ctx.setFillColor(NSColor.red.withAlphaComponent(0.9).cgColor)
            } else {
                ctx.setFillColor(NSColor.green.withAlphaComponent(0.6).cgColor)
            }
            for point in faceKeypoints {
                let x = point.x * w
                let y = point.y * h   // Vision 坐标系 Y 向下，NSView 也是 Y 向下，直接映射
                let rect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                ctx.fillEllipse(in: rect)
            }
        }

        // --- 绘制手部关键点 (半径4pt) ---
        if !handKeypoints.isEmpty {
            ctx.setShouldAntialias(true)
            if isCommandActive {
                ctx.setFillColor(NSColor.red.withAlphaComponent(0.9).cgColor)
            } else {
                ctx.setFillColor(NSColor.green.withAlphaComponent(0.8).cgColor)
            }
            for point in handKeypoints {
                let x = point.x * w
                let y = point.y * h
                let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                ctx.fillEllipse(in: rect)
            }
        }
    }

    // 如果不希望背景被绘制，可以覆写 isFlipped 返回 true（NSView 默认就是 true）
    override var isFlipped: Bool { true }
}
