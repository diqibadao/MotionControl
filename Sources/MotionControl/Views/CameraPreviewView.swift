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
        nsView.overlayLayer?.setNeedsDisplay()
    }
}

// MARK: - 自定义 NSView，完成预览+叠加绘制
class OverlayPreviewNSView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    var overlayLayer: CALayer?
    var handKeypoints: [CGPoint] = []
    var faceKeypoints: [CGPoint] = []
    var isCommandActive: Bool = false
    var frameSize: CGSize = .zero

    // 手部骨骼连接索引（与 MovementsApp.swift 保持一致）
    private let handConnections: [(Int, Int)] = [
        (0,3), (3,2), (2,1),                                     // 拇指
        (0,7), (7,6), (6,5), (5,4),                             // 食指
        (0,11), (11,10), (10,9), (9,8),                         // 中指
        (0,15), (15,14), (14,13), (13,12),                      // 无名指
        (0,19), (19,18), (18,17), (17,16),                      // 小指
        (3,7), (7,11), (11,15), (15,19)                         // 掌骨
    ]

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // 在 previewLayer 上方加一个透明叠加层用于绘制
        if overlayLayer == nil, let superLayer = self.layer {
            let ol = CALayer()
            ol.frame = self.bounds
            ol.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            ol.isOpaque = false
            ol.delegate = self
            superLayer.addSublayer(ol)  // 加到 previewLayer 上方
            self.overlayLayer = ol
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 空的，所有绘制挪到 overlayLayer 的 delegate 方法中
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        overlayLayer?.frame = bounds
    }
}

extension OverlayPreviewNSView: CALayerDelegate {
    func draw(_ layer: CALayer, in ctx: CGContext) {
        guard layer === overlayLayer else { return }
        
        // 调试：打印坐标系信息
        print("[OVERLAY-CTX] isFlipped=\(isFlipped) ctm=\(ctx.ctm) bounds=\(layer.bounds)")
        
        // Vision 归一化坐标 → 视图坐标（手动计算 videoRect）
        func visionPointToView(_ point: CGPoint) -> CGPoint {
            let camW = frameSize.width > 0 ? frameSize.width : 1920
            let camH = frameSize.height > 0 ? frameSize.height : 1080
            let cameraAspect = camW / camH
            let viewAspect = layer.bounds.width / layer.bounds.height
            let videoRect: CGRect
            if viewAspect > cameraAspect {
                let videoH = layer.bounds.height
                let videoW = videoH * cameraAspect
                let xOff = (layer.bounds.width - videoW) / 2
                videoRect = CGRect(x: xOff, y: 0, width: videoW, height: videoH)
            } else {
                let videoW = layer.bounds.width
                let videoH = videoW / cameraAspect
                let yOff = (layer.bounds.height - videoH) / 2
                videoRect = CGRect(x: 0, y: yOff, width: videoW, height: videoH)
            }
            // 调试：打印第一帧的坐标信息
            if point == handKeypoints.first ?? point {
                print("[OVERLAY] bounds=\(bounds) videoRect=\(videoRect) frameSize=\(frameSize) firstPt=\(point)")
            }
            // View 坐标系 y 向上，与 Vision 一致，无需翻转
            let x = point.x * videoRect.width + videoRect.origin.x
            let y = point.y * videoRect.height + videoRect.origin.y
            return CGPoint(x: x, y: y)
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
                print("[OVERLAY-DRAW] pt=\(point) display=\(displayPoint) bounds=\(bounds)")
                let rect = CGRect(x: displayPoint.x - 4, y: displayPoint.y - 4,
                                  width: 8, height: 8)
                ctx.fillEllipse(in: rect)
            }
        }
    }
}
