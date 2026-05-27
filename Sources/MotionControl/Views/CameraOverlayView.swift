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

        // 1. 计算视频画面在视图中的实际矩形（4:3 aspect ratio，.resizeAspect）
        let cameraAspect: CGFloat = 640.0 / 480.0
        let viewAspect = w / h
        let videoRect: CGRect
        if viewAspect > cameraAspect {
            let videoHeight = h
            let videoWidth = videoHeight * cameraAspect
            let xOffset = (w - videoWidth) / 2
            videoRect = CGRect(x: xOffset, y: 0, width: videoWidth, height: videoHeight)
        } else {
            let videoWidth = w
            let videoHeight = videoWidth / cameraAspect
            let yOffset = (h - videoHeight) / 2
            videoRect = CGRect(x: 0, y: yOffset, width: videoWidth, height: videoHeight)
        }

        // 2. 辅助函数：Vision 归一化坐标 → NSView 坐标
        func visionPointToView(_ point: CGPoint, videoRect: CGRect) -> CGPoint {
            let x = point.x * videoRect.width + videoRect.origin.x
            let y = (1.0 - point.y) * videoRect.height + videoRect.origin.y
            return CGPoint(x: x, y: y)
        }

        // --- 绘制面部特征点 (半径2pt) ---
        if !faceKeypoints.isEmpty {
            ctx.setShouldAntialias(true)
            if isCommandActive {
                ctx.setFillColor(NSColor.red.withAlphaComponent(0.9).cgColor)
            } else {
                ctx.setFillColor(NSColor.green.withAlphaComponent(0.6).cgColor)
            }
            for point in faceKeypoints {
                let displayPoint = visionPointToView(point, videoRect: videoRect)
                let rect = CGRect(x: displayPoint.x - 2, y: displayPoint.y - 2, width: 4, height: 4)
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
                let displayPoint = visionPointToView(point, videoRect: videoRect)
                let rect = CGRect(x: displayPoint.x - 4, y: displayPoint.y - 4, width: 8, height: 8)
                ctx.fillEllipse(in: rect)
            }
        }
    }

    // 如果不希望背景被绘制，可以覆写 isFlipped 返回 true（NSView 默认就是 true）
    override var isFlipped: Bool { true }
}
