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

        // 2. 辅助函数：Vision 归一化坐标 → NSView 坐标（x镜像，y翻转）
        func visionPointToView(_ point: CGPoint, videoRect: CGRect) -> CGPoint {
            let x = (1.0 - point.x) * videoRect.width + videoRect.origin.x
            let y = (1.0 - point.y) * videoRect.height + videoRect.origin.y
            return CGPoint(x: x, y: y)
        }

        // --- 定义手部骨骼连接索引（基于 MotionControlApp.swift 中的追加顺序）---
        // 索引顺序：wrist(0), thumbTip(1), thumbIP(2), thumbMP(3),
        // indexTip(4), indexDIP(5), indexPIP(6), indexMCP(7),
        // middleTip(8), middleDIP(9), middlePIP(10), middleMCP(11),
        // ringTip(12), ringDIP(13), ringPIP(14), ringMCP(15),
        // littleTip(16), littleDIP(17), littlePIP(18), littleMCP(19)
        let handConnections: [(Int, Int)] = [
            // 拇指：wrist→thumbMP→thumbIP→thumbTip
            (0,3), (3,2), (2,1),
            // 食指：wrist→indexMCP→indexPIP→indexDIP→indexTip
            (0,7), (7,6), (6,5), (5,4),
            // 中指：wrist→middleMCP→middlePIP→middleDIP→middleTip
            (0,11), (11,10), (10,9), (9,8),
            // 无名指：wrist→ringMCP→ringPIP→ringDIP→ringTip
            (0,15), (15,14), (14,13), (13,12),
            // 小指：wrist→littleMCP→littlePIP→littleDIP→littleTip
            (0,19), (19,18), (18,17), (17,16),
            // 掌骨连接：thumbMP→indexMCP→middleMCP→ringMCP→littleMCP
            (3,7), (7,11), (11,15), (15,19)
        ]

        // --- 绘制手部骨骼连线（白色半透明）---
        if handKeypoints.count >= 20 {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setShouldAntialias(true)

            for (idx1, idx2) in handConnections {
                guard idx1 < handKeypoints.count, idx2 < handKeypoints.count else { continue }
                let pt1 = visionPointToView(handKeypoints[idx1], videoRect: videoRect)
                let pt2 = visionPointToView(handKeypoints[idx2], videoRect: videoRect)
                ctx.beginPath()
                ctx.move(to: pt1)
                ctx.addLine(to: pt2)
                ctx.strokePath()
            }
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
