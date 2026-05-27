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
    private let mouthDetector = MouthDetector()
    // 注视追踪改为直接从 FaceResult 读取角度，不再使用 GazeEstimator

    var onGesture: ((GestureEvent) -> Void)?
    var onMouthEvent: ((MouthEvent) -> Void)?
    var onGaze: ((GazeEstimate) -> Void)?   // 类型改为 GazeEstimate
    var onHandResult: ((HandPoseResult?) -> Void)?
    var onFaceResult: ((FaceResult?) -> Void)?

    private var isRunning = false
    private let processingQueue = DispatchQueue(label: "com.motioncontrol.detection", qos: .userInteractive)

    private var lastHand: HandPoseResult?
    private var lastFace: FaceResult?

    private var frameCount = 0

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
        guard frameCount % 5 == 0 else { return }
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
            } else {
                DispatchQueue.main.async {
                    self.onHandResult?(nil)
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
                // 直接使用面部欧拉角发出 GazeEstimate
                self.didOutputFace(faceResult)
            } else {
                DispatchQueue.main.async {
                    self.onFaceResult?(nil)
                }
            }
        }
    }

    func didOutputFace(_ face: FaceResult) {
        let estimate = GazeEstimate(
            yawOffset: face.yaw ?? 0,
            pitchOffset: face.pitch ?? 0,
            hasFace: true
        )
        DispatchQueue.main.async {
            self.onGaze?(estimate)
        }
    }

    func didOutputHand(_ hand: HandPoseResult) {
        // 暂不实现
    }
}
