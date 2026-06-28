import Foundation
import AVFoundation
import Vision
import AppKit

protocol CameraOutputDelegate: AnyObject {
    func didOutputFrame(_ sampleBuffer: CMSampleBuffer)
    func didOutputFace(_ face: FaceResult)
    func didOutputHand(_ hand: HandPoseResult)
}

class DetectionPipeline: CameraOutputDelegate {
    private let handPoseDetector = HandPoseDetector()
    private let faceMeshDetector = FaceMeshDetector()
    private let gestureAnalyzer = GestureAnalyzer()
    
    /// 当前是否捏合中（供光标冻结使用）
    var isPinching: Bool { gestureAnalyzer.isPinching }
    var cursorFrozen: Bool { gestureAnalyzer.cursorFrozen }
    private let mouthDetector = MouthDetector()
    private let gazeEstimator = GazeEstimator()   // 新增注视跟踪器

    var onGesture: ((GestureEvent) -> Void)?
    var onMouthEvent: ((MouthEvent) -> Void)?
    var onGaze: ((GazeEstimate) -> Void)?   // 类型改为 GazeEstimate
    var onHandResult: ((HandPoseResult?, TimeInterval) -> Void)?
    var onFaceResult: ((FaceResult?) -> Void)?

    private var isRunning = false
    private let processingQueue = DispatchQueue(label: "com.motioncontrol.detection", qos: .userInteractive)

    private var lastHand: HandPoseResult?
    private var lastFace: FaceResult?

    private var frameCount = 0
    private var lastProcessedTime: Date = .distantPast

    init() {}

    func start() {
        isRunning = true
        frameCount = 0
    }

    func stop() {
        isRunning = false
        lastHand = nil
        lastFace = nil
        frameCount = 0
    }

    func didOutputFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        frameCount += 1
        // 全帧处理，不再跳帧
        // guard frameCount % 2 == 0 else { return }
        let now = Date()
        let frameDt: TimeInterval = lastProcessedTime == .distantPast ? (1.0 / 15.0) : now.timeIntervalSince(lastProcessedTime)
        lastProcessedTime = now
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            // 手部检测
            if let handResult = self.handPoseDetector.detect(in: sampleBuffer) {
                self.lastHand = handResult
                let gestureEvent = self.gestureAnalyzer.analyze(handResult)
                DispatchQueue.main.async {
                    self.onGesture?(gestureEvent)
                    self.onHandResult?(handResult, frameDt)
                }
            } else {
                DispatchQueue.main.async {
                    self.onHandResult?(nil, 1.0/15.0)
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
                // 使用 GazeEstimator 获得注视估计
                self.didOutputFace(faceResult)
            } else {
                DispatchQueue.main.async {
                    self.onFaceResult?(nil)
                }
            }
        }
    }

    func didOutputFace(_ face: FaceResult) {
        Task {
            let est = await gazeEstimator.estimate(from: face)
            DispatchQueue.main.async {
                self.onGaze?(est)
            }
        }
    }

    func didOutputHand(_ hand: HandPoseResult) {
        // 暂不实现
    }

    /// 启动注视校准
    func startGazeCalibration() {
        Task {
            await gazeEstimator.autoCalibrate()
        }
    }
}
