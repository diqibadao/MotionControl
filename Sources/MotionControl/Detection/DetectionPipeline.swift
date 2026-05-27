import Foundation
import AVFoundation
import Vision

/// 摄像头输出代理协议（由 DetectionPipeline 实现）
public protocol CameraOutputDelegate: AnyObject {
    func didOutputFrame(_ sampleBuffer: CMSampleBuffer)
    func didOutputFace(_ face: FaceResult)
    func didOutputHand(_ hand: HandPoseResult)
}

/// 检测管道：串联摄像头 → 手部/人脸检测 → 手势/嘴部分析 → 输出事件
public class DetectionPipeline: CameraOutputDelegate {
    // MARK: - 子模块
    private let handPoseDetector = HandPoseDetector()
    private let faceMeshDetector = FaceMeshDetector()
    private let gestureAnalyzer = GestureAnalyzer()
    private let mouthDetector = MouthDetector()

    // 输出闭包
    public var onGesture: ((GestureEvent) -> Void)?
    public var onMouthEvent: ((MouthEvent) -> Void)?

    // 运行状态
    private var isRunning = false
    private let processingQueue = DispatchQueue(label: "com.motioncontrol.detection", qos: .userInteractive)

    // 保存最近一次手部/人脸结果
    private var lastHand: HandPoseResult?
    private var lastFace: FaceResult?

    public init() {}

    // MARK: - 启动/停止
    public func start() {
        isRunning = true
        // 实际启动摄像头需要外部调用，此处仅设置标志
    }

    public func stop() {
        isRunning = false
        lastHand = nil
        lastFace = nil
    }

    // MARK: - CameraOutputDelegate
    public func didOutputFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            // 手部检测
            if let handResult = self.handPoseDetector.detect(in: sampleBuffer) {
                self.lastHand = handResult
                let gestureEvent = self.gestureAnalyzer.analyze(handResult)
                DispatchQueue.main.async {
                    self.onGesture?(gestureEvent)
                }
            }
            // 人脸检测
            if let faceResult = self.faceMeshDetector.detect(in: sampleBuffer) {
                self.lastFace = faceResult
                let mouthEvent = self.mouthDetector.detect(from: faceResult)
                DispatchQueue.main.async {
                    self.onMouthEvent?(mouthEvent)
                }
            }
        }
    }

    public func didOutputFace(_ face: FaceResult) {
        // 如果已从 didOutputFrame 中调用，这里可留空
    }

    public func didOutputHand(_ hand: HandPoseResult) {
        // 同上
    }
}
