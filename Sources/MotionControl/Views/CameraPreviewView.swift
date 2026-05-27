import SwiftUI
import AVFoundation

/// 摄像头预览视图（NSViewRepresentable），集成叠加绘制
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    var handKeypoints: [CGPoint] = []
    var faceKeypoints: [CGPoint] = []
    var isCommandActive: Bool = false
    var frameSize: CGSize = .zero

    func makeNSView(context: Context) -> OverlayPreviewNSView {
        let view = OverlayPreviewNSView()
        view.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.videoGravity = .resizeAspect
        view.layer?.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        return view
    }

    func updateNSView(_ nsView: OverlayPreviewNSView, context: Context) {
        nsView.handKeypoints = handKeypoints
        nsView.faceKeypoints = faceKeypoints
        nsView.isCommandActive = isCommandActive
        nsView.frameSize = frameSize

        // 更新 previewLayer 尺寸
        if let layer = nsView.previewLayer {
            layer.frame = nsView.bounds
        }

        nsView.needsDisplay = true
    }
}

// MARK: - 自定义 NSView，完成预览+叠加绘制
class OverlayPreviewNSView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    var handKeypoints: [CGPoint] = []
    var faceKeypoints: [CGPoint] = []
    var isCommandActive: Bool = false
    var frameSize: CGSize = .zero

    override var isFlipped: Bool { true }

    // 手部骨骼连接索引（与 MovementsApp.swift 保持一致）
    private let handConnections: [(Int, Int)] = [
        (0,3), (3,2), (2,1),                                     // 拇指
        (0,7), (7,6), (6,5), (5,4),                             // 食指
        (0,11), (11,10), (10,9), (9,8),                         // 中指
        (0,15), (15,14), (14,13), (13,12),                      // 无名指
        (0,19), (19,18), (18,17), (17,16),                      // 小指
        (3,7), (7,11), (11,15), (15,19)                         // 掌骨
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext,
              let previewLayer = previewLayer else { return }

        // Vision 归一化坐标 → 视图坐标（y‑up → y‑down）
        func visionPointToView(_ point: CGPoint) -> CGPoint {
            let devicePoint = CGPoint(x: point.x, y: 1.0 - point.y)
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
        }

        // --- 绘制手部骨骼连线 ---
        if handKeypoints.count >= 20 {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setShouldAntialias(true)

            for (idx1, idx2) in handConnections {
                guard idx1 < handKeypoints.count, idx2 < handKeypoints.count else { continue }
                let pt1 = visionPointToView(handKeypoints[idx1])
                let pt2 = visionPointToView(handKeypoints[idx2])
                ctx.beginPath()
                ctx.move(to: pt1)
                ctx.addLine(to: pt2)
                ctx.strokePath()
            }
        }

        // --- 绘制面部特征点 ---
        if !faceKeypoints.isEmpty {
            ctx.setShouldAntialias(true)
            ctx.setFillColor(
                isCommandActive
                    ? NSColor.red.withAlphaComponent(0.9).cgColor
                    : NSColor.green.withAlphaComponent(0.6).cgColor
            )
            for point in faceKeypoints {
                let displayPoint = visionPointToView(point)
                let rect = CGRect(x: displayPoint.x - 2, y: displayPoint.y - 2,
                                  width: 4, height: 4)
                ctx.fillEllipse(in: rect)
            }
        }

        // --- 绘制手部关键点 ---
        if !handKeypoints.isEmpty {
            ctx.setShouldAntialias(true)
            ctx.setFillColor(
                isCommandActive
                    ? NSColor.red.withAlphaComponent(0.9).cgColor
                    : NSColor.green.withAlphaComponent(0.8).cgColor
            )
            for point in handKeypoints {
                let displayPoint = visionPointToView(point)
                let rect = CGRect(x: displayPoint.x - 4, y: displayPoint.y - 4,
                                  width: 8, height: 8)
                ctx.fillEllipse(in: rect)
            }
        }
    }
}
