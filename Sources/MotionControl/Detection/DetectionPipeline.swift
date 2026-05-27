import Foundation
import AVFoundation
import Vision
import AppKit

/// 摄像头输出代理协议（由 DetectionPipeline 实现）
protocol CameraOutputDelegate: AnyObject {
    func didOutputFrame(_ sampleBuffer: CMSampleBuffer)
    func didOutputFace(_ face: FaceResult)
    func didOutputHand(_ hand: HandPoseResult)
}

/// 检测管道：串联摄像头 → 手部/人脸检测 → 手势/嘴部分析 → 输出事件
class DetectionPipeline: CameraOutputDelegate {
    // MARK: - 子模块
    private let handPoseDetector = HandPoseDetector()
    private let faceMeshDetector = FaceMeshDetector()
    private let gestureAnalyzer = GestureAnalyzer()
    private let mouthDetector = MouthDetector()
    private let gazeEstimator = GazeEstimator()

    // 输出闭包
    var onGesture: ((GestureEvent) -> Void)?
    var onMouthEvent: ((MouthEvent) -> Void)?
    var onGaze: ((GazePoint) -> Void)?
    var onHandResult: ((HandPoseResult) -> Void)?
    var onFaceResult: ((FaceResult) -> Void)?

    // 运行状态
    private var isRunning = false
    private let processingQueue = DispatchQueue(label: "com.motioncontrol.detection", qos: .userInteractive)

    // 保存最近一次手部/人脸结果
    private var lastHand: HandPoseResult?
    private var lastFace: FaceResult?

    // 帧计数器（每5帧检测一次）
    private var frameCount = 0

    init() {}

    // MARK: - 启动/停止
    func start() {
        isRunning = true
        frameCount = 0
        // 实际启动摄像头需要外部调用，此处仅设置标志
    }

    func stop() {
        isRunning = false
        lastHand = nil
        lastFace = nil
        frameCount = 0
    }

    // MARK: - CameraOutputDelegate
    func didOutputFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        frameCount += 1
        guard frameCount % 5 == 0 else { return } // 每5帧处理一次
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            // 手部检测
            if let handResult = self.handPoseDetector.detect(in: sampleBuffer) {
                self.lastHand = handResult
                let gestureEvent = self.gestureAnalyzer.analyze(handResult)
                DispatchQueue.main.async {
                    self.onGesture?(gestureEvent)
                    self.onHandResult?(handResult)
                }
            }
            // 人脸检测
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            if let faceResults = self.faceMeshDetector.detect(pixelBuffer: pixelBuffer),
              let faceResult = faceResults.first {
                self.lastFace = faceResult
                let mouthEvent = self.mouthDetector.detect(from: faceResult)
                DispatchQueue.main.async {
                    self.onMouthEvent?(mouthEvent)
                    self.onFaceResult?(faceResult)
                }
                // 新增人脸凝视估计
                self.didOutputFace(faceResult)
            }
        }
    }

    func didOutputFace(_ face: FaceResult) {
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        Task {
            let gazeResult = await gazeEstimator.estimate(from: face, screenSize: screenSize)
            DispatchQueue.main.async {
                self.onGaze?(gazeResult)
            }
        }
    }

    func didOutputHand(_ hand: HandPoseResult) {
        // 同上
    }
}
