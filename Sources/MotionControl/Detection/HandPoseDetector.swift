import Foundation
import Vision
import CoreGraphics
import CoreMedia

/// 手指枚举，用于 fingerExtension 返回的字典键
enum HandFinger: String, CaseIterable {
    case thumb
    case index
    case middle
    case ring
    case little
}

/// 手部 21 个关键点检测结果
struct HandPoseResult {
    // 手腕
    var wrist: CGPoint?
    // 拇指
    var thumbTip: CGPoint?
    var thumbIP: CGPoint?   // 拇指指间关节
    var thumbMP: CGPoint?   // 拇指掌指关节
    // 食指
    var indexTip: CGPoint?
    var indexDIP: CGPoint?
    var indexPIP: CGPoint?
    var indexMCP: CGPoint?
    // 中指
    var middleTip: CGPoint?
    var middleDIP: CGPoint?
    var middlePIP: CGPoint?
    var middleMCP: CGPoint?
    // 无名指
    var ringTip: CGPoint?
    var ringDIP: CGPoint?
    var ringPIP: CGPoint?
    var ringMCP: CGPoint?
    // 小指
    var littleTip: CGPoint?
    var littleDIP: CGPoint?
    var littlePIP: CGPoint?
    var littleMCP: CGPoint?

    /// 从 VNHumanHandPoseObservation 初始化
    init?(observation: VNHumanHandPoseObservation) {
        guard let allPoints = try? observation.recognizedPoints(.all) else { return nil }

        /// 提取指定关节的归一化坐标（若置信度 > 0）
        func point(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = allPoints[joint], p.confidence > 0 else { return nil }
            return p.location
        }

        wrist        = point(.wrist)
        thumbTip     = point(.thumbTip)
        thumbIP      = point(.thumbIP)
        thumbMP      = point(.thumbMP)
        indexTip     = point(.indexTip)
        indexDIP     = point(.indexDIP)
        indexPIP     = point(.indexPIP)
        indexMCP     = point(.indexMCP)
        middleTip    = point(.middleTip)
        middleDIP    = point(.middleDIP)
        middlePIP    = point(.middlePIP)
        middleMCP    = point(.middleMCP)
        ringTip      = point(.ringTip)
        ringDIP      = point(.ringDIP)
        ringPIP      = point(.ringPIP)
        ringMCP      = point(.ringMCP)
        littleTip    = point(.littleTip)
        littleDIP    = point(.littleDIP)
        littlePIP    = point(.littlePIP)
        littleMCP    = point(.littleMCP)
    }

    /// 手掌中心（手腕 + 四根手指的 MCP 的平均点）
    var palmCenter: CGPoint? {
        let candidates = [wrist, indexMCP, middleMCP, ringMCP, littleMCP]
        let valid = candidates.compactMap { $0 }
        guard !valid.isEmpty else { return nil }
        let avgX = valid.reduce(0) { $0 + $1.x } / CGFloat(valid.count)
        let avgY = valid.reduce(0) { $0 + $1.y } / CGFloat(valid.count)
        return CGPoint(x: avgX, y: avgY)
    }

    /// 拇指指尖到食指指尖的欧氏距离
    /// - Returns: 像素距离（归一化坐标下的距离）
    func thumbIndexDistance() -> CGFloat? {
        guard let thumb = thumbTip, let index = indexTip else { return nil }
        let dx = thumb.x - index.x
        let dy = thumb.y - index.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 拇指指尖到中指指尖的欧氏距离
    func thumbMiddleDistance() -> CGFloat? {
        guard let thumb = thumbTip, let middle = middleTip else { return nil }
        let dx = thumb.x - middle.x
        let dy = thumb.y - middle.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 每根手指的伸展程度（指尖到 MCP 的距离）
    /// - Returns: 字典，键为 `HandFinger` 枚举，值为距离（归一化坐标，`CGFloat`）
    func fingerExtension() -> [HandFinger: CGFloat] {
        var result = [HandFinger: CGFloat]()

        func distance(_ tip: CGPoint?, _ mcp: CGPoint?) -> CGFloat? {
            guard let t = tip, let m = mcp else { return nil }
            let dx = t.x - m.x
            let dy = t.y - m.y
            return sqrt(dx * dx + dy * dy)
        }

        result[.thumb]  = distance(thumbTip,  thumbMP)
        result[.index]  = distance(indexTip,  indexMCP)
        result[.middle] = distance(middleTip, middleMCP)
        result[.ring]   = distance(ringTip,   ringMCP)
        result[.little] = distance(littleTip, littleMCP)

        return result
    }
}

/// 手部关键点检测器，封装 VNDetectHumanHandPoseRequest
@available(macOS 11.0, iOS 14.0, *)
class HandPoseDetector {
    private let request = VNDetectHumanHandPoseRequest()

    /// 从 CMSampleBuffer 检测第一只手的关键点
    /// - Parameter sampleBuffer: 视频帧样本缓冲
    /// - Returns: 检测结果，若未检测到手则返回 nil
    func detect(in sampleBuffer: CMSampleBuffer) -> HandPoseResult? {
        // 获取图像尺寸
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let width: Int
        let height: Int
        if let pb = pixelBuffer {
            width = CVPixelBufferGetWidth(pb)
            height = CVPixelBufferGetHeight(pb)
        } else {
            width = 0
            height = 0
        }
        let frameSizeStr = "\(width)x\(height)"
        let input = "hand_detect \(frameSizeStr)"

        guard let pb = pixelBuffer else {
            let output = "detected=false landmarks=nil confidence=0"
            EventLogger.log(event: "hand_detect", frame: nil, input: input, output: output, duration: nil)
            return nil
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pb, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("HandPose detection failed: \(error)")
            let output = "detected=false landmarks=nil confidence=0"
            EventLogger.log(event: "hand_detect", frame: nil, input: input, output: output, duration: nil)
            return nil
        }

        guard let observation = request.results?.first else {
            let output = "detected=false landmarks=nil confidence=0"
            EventLogger.log(event: "hand_detect", frame: nil, input: input, output: output, duration: nil)
            return nil
        }

        let result = HandPoseResult(observation: observation)

        // 获取手腕置信度作为代表
        let wristConfidence: Float
        if let allPoints = try? observation.recognizedPoints(.all),
           let wristPoint = allPoints[.wrist] {
            wristConfidence = wristPoint.confidence
        } else {
            wristConfidence = 0
        }

        let output: String
        if result != nil {
            output = "detected=true landmarks=21 confidence=\(wristConfidence)"
        } else {
            output = "detected=false landmarks=nil confidence=0"
        }

        EventLogger.log(event: "hand_detect", frame: nil, input: input, output: output, duration: nil)
        return result
    }
}
