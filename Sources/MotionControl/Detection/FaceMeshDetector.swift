//
//  FaceMeshDetector.swift
//  MotionControl
//

import Vision
import CoreGraphics
import Foundation

// MARK: - 面部检测结果
/// 存储检测到的面部结构：头部姿态、眼睑轮廓、瞳孔、嘴唇及面部轮廓。
struct FaceResult {
    let roll: Float?
    let pitch: Float?
    let yaw: Float?

    /// 左眼睑点集（归一化坐标 0~1）
    let leftEye: [CGPoint]?
    /// 右眼睑点集
    let rightEye: [CGPoint]?
    /// 左瞳孔（单个点）
    let leftPupil: CGPoint?
    /// 右瞳孔
    let rightPupil: CGPoint?
    /// 外嘴唇点集
    let outerLips: [CGPoint]?
    /// 内嘴唇点集
    let innerLips: [CGPoint]?
    /// 面部轮廓点集
    let faceContour: [CGPoint]?

    // MARK: - 嘴开合比
    /// 基于外嘴唇包围盒的高度/宽度比，0 ~ 1 之间。
    var mouthOpenRatio: Float {
        guard let lips = outerLips, lips.count >= 4 else { return 0 }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNormalMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = CGFloat.leastNormalMagnitude
        for point in lips {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0 else { return 0 }
        return Float(height / width)
    }

    // MARK: - 获取有效瞳孔
    /// 返回任意一个有效的瞳孔点（优先左眼，后右眼）。
    func anyPupil() -> CGPoint? {
        if let left = leftPupil { return left }
        if let right = rightPupil { return right }
        return nil
    }
}

// MARK: - 面部特征点检测器
/// 使用 Vision 框架的 VNDetectFaceLandmarksRequest 检测 76 点面部星座。
class FaceMeshDetector {
    init() {}

    /// 对给定的像素缓冲区执行面部特征点检测。
    /// - Parameter pixelBuffer: 视频帧的 CVPixelBuffer。
    /// - Returns: 包含所有检测到的人脸的 `FaceResult` 数组，若无检测则返回 nil。
    func detect(pixelBuffer: CVPixelBuffer) -> [FaceResult]? {
        let start = CFAbsoluteTimeGetCurrent()

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            let output = "detected=false landmarks=nil roll=nil pitch=nil yaw=nil"
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            EventLogger.log(event: "face_detect",
                            frame: nil,
                            input: "face_detect",
                            output: output,
                            duration: duration)
            print("面部检测失败：\(error)")
            return nil
        }
        guard let observations = request.results as? [VNFaceObservation] else {
            let output = "detected=false landmarks=nil roll=nil pitch=nil yaw=nil"
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            EventLogger.log(event: "face_detect",
                            frame: nil,
                            input: "face_detect",
                            output: output,
                            duration: duration)
            return nil
        }

        let results = observations.map { Self.faceResult(from: $0) }

        let output: String
        if let first = results.first {
            let rollStr = first.roll.map { "\($0)" } ?? "nil"
            let pitchStr = first.pitch.map { "\($0)" } ?? "nil"
            let yawStr = first.yaw.map { "\($0)" } ?? "nil"
            output = "detected=true landmarks=76 roll=\(rollStr) pitch=\(pitchStr) yaw=\(yawStr)"
        } else {
            output = "detected=false landmarks=nil roll=nil pitch=nil yaw=nil"
        }

        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        EventLogger.log(event: "face_detect",
                        frame: nil,
                        input: "face_detect",
                        output: output,
                        duration: duration)

        return results
    }

    // MARK: - 私有辅助方法
    /// 将人脸特征点从人脸框相对坐标转为图像绝对坐标。
    private static func landmarkPoints(from landmark: VNFaceLandmarkRegion2D?, in boundingBox: CGRect) -> [CGPoint]? {
        guard let points = landmark?.normalizedPoints else { return nil }
        return points.map { point in
            let x = boundingBox.origin.x + point.x * boundingBox.width
            let y = boundingBox.origin.y + point.y * boundingBox.height
            return CGPoint(x: x, y: y)
        }
    }

    /// 从 VNFaceObservation 构建 FaceResult。
    private static func faceResult(from observation: VNFaceObservation) -> FaceResult {
        let landmarks = observation.landmarks
        let bbox = observation.boundingBox

        // 头部姿态（欧拉角）
        let roll = observation.roll?.floatValue
        let pitch = observation.pitch?.floatValue
        let yaw = observation.yaw?.floatValue

        // 眼睑轮廓
        let leftEye = Self.landmarkPoints(from: landmarks?.leftEye, in: bbox)
        let rightEye = Self.landmarkPoints(from: landmarks?.rightEye, in: bbox)

        // 瞳孔（每个区域只有一个点）
        let leftPupil = Self.landmarkPoints(from: landmarks?.leftPupil, in: bbox)?.first
        let rightPupil = Self.landmarkPoints(from: landmarks?.rightPupil, in: bbox)?.first

        // 嘴唇（保持归一化坐标，不转换为绝对坐标）
        let outerLips = landmarks?.outerLips?.normalizedPoints?.map { $0.pointValue }
        let innerLips = landmarks?.innerLips?.normalizedPoints?.map { $0.pointValue }

        // 面部轮廓
        let faceContour = Self.landmarkPoints(from: landmarks?.faceContour, in: bbox)

        return FaceResult(
            roll: roll,
            pitch: pitch,
            yaw: yaw,
            leftEye: leftEye,
            rightEye: rightEye,
            leftPupil: leftPupil,
            rightPupil: rightPupil,
            outerLips: outerLips,
            innerLips: innerLips,
            faceContour: faceContour
        )
    }
}
