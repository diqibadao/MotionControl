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
    /// 外嘴唇点集（归一化坐标 0~1）
    let outerLips: [CGPoint]?
    /// 内嘴唇点集（归一化坐标 0~1）
    let innerLips: [CGPoint]?
    /// 外嘴唇点集（绝对坐标）
    let outerLipsAbsolute: [CGPoint]?
    /// 内嘴唇点集（绝对坐标）
    let innerLipsAbsolute: [CGPoint]?
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
/// 使用 Vision 框架的 VNDetectFaceLandmarksRequest 检测 76 点面部星座，
/// 并配合 VNDetectFaceRectanglesRequest Revision 3 获取准确的头部姿态。
class FaceMeshDetector {
    
    // 新增：隔帧缓存与计数器
    private var poseFrameCounter: Int = 0
    private var lastPoseRoll: Float? = nil
    private var lastPosePitch: Float? = nil
    private var lastPoseYaw: Float? = nil

    init() {}

    /// 对给定的像素缓冲区执行面部特征点检测。
    /// - Parameter pixelBuffer: 视频帧的 CVPixelBuffer。
    /// - Returns: 包含所有检测到的人脸的 `FaceResult` 数组，若无检测则返回 nil。
    func detect(pixelBuffer: CVPixelBuffer) -> [FaceResult]? {
        let start = CFAbsoluteTimeGetCurrent()

        // 1. 只创建 landmarksRequest（特征点请求总是执行）
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        let perfStart = CFAbsoluteTimeGetCurrent()
        do {
            try handler.perform([landmarksRequest])
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
        let perfDuration = Int((CFAbsoluteTimeGetCurrent() - perfStart) * 1000)
        print("[FACE-PERF] landmarks perform took \(perfDuration)ms")

        // 2. 获取人脸 landmarks 观测值
        let landmarkObs = landmarksRequest.results as? [VNFaceObservation]

        // 没有检测到人脸
        guard let landmarkObservations = landmarkObs, !landmarkObservations.isEmpty else {
            let output = "detected=false landmarks=nil roll=nil pitch=nil yaw=nil"
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            EventLogger.log(event: "face_detect",
                            frame: nil,
                            input: "face_detect",
                            output: output,
                            duration: duration)
            return nil
        }

        // 3. 隔帧获取姿态（每 15 帧执行一次 faceRectRequest）
        var poseObservation: VNFaceObservation? = nil
        if poseFrameCounter % 15 == 0 {
            let rectStart = CFAbsoluteTimeGetCurrent()
            let faceRectRequest = VNDetectFaceRectanglesRequest()
            faceRectRequest.revision = VNDetectFaceRectanglesRequestRevision3
            // 创建新 handler 执行 faceRectRequest（复用同一个 pixelBuffer）
            let poseHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                    orientation: .up,
                                                    options: [:])
            do {
                try poseHandler.perform([faceRectRequest])
                let rectObs = faceRectRequest.results as? [VNFaceObservation]
                poseObservation = rectObs?.first
                // 更新缓存
                lastPoseRoll = poseObservation?.roll?.floatValue
                lastPosePitch = poseObservation?.pitch?.floatValue
                lastPoseYaw = poseObservation?.yaw?.floatValue
            } catch {
                // 姿态请求失败，保持上次缓存
                print("姿态请求失败：\(error)")
            }
            let rectDuration = Int((CFAbsoluteTimeGetCurrent() - rectStart) * 1000)
            print("[FACE-PERF] faceRect perform took \(rectDuration)ms")
        } else {
            // 不用新跑 request，使用缓存
            // 我们仍然需要构造一个 poseObservation 来传递缓存值？但 faceResult 方法期望的是 VNFaceObservation? 
            // 这里我们不构造实际对象，而是在 faceResult 中直接使用缓存值。
            // 做法：不传入 poseObservation，而让 faceResult 方法从缓存读取。
            poseObservation = nil // 使用缓存
        }
        poseFrameCounter += 1

        // 4. 构建 FaceResult
        let results = landmarkObservations.map { observation in
            Self.faceResult(landmarkObservation: observation,
                            poseObservation: poseObservation, // 只在有 request 时才传入，否则为 nil
                            cachedRoll: lastPoseRoll,
                            cachedPitch: lastPosePitch,
                            cachedYaw: lastPoseYaw)
        }

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

    /// 结合面部特征点观测和头部姿态观测构建 FaceResult。
    /// - Parameters:
    ///   - landmarkObservation: VNDetectFaceLandmarksRequest 的结果，提供 76 个特征点。
    ///   - poseObservation: VNDetectFaceRectanglesRequest Revision 3 的结果，提供 yaw/pitch/roll。
    ///                       若为 nil，则尝试使用缓存值。
    ///   - cachedRoll, cachedPitch, cachedYaw: 隔帧缓存的姿态值（当 poseObservation 为 nil 时使用）
    private static func faceResult(landmarkObservation: VNFaceObservation,
                                   poseObservation: VNFaceObservation?,
                                   cachedRoll: Float? = nil,
                                   cachedPitch: Float? = nil,
                                   cachedYaw: Float? = nil) -> FaceResult {
        let landmarks = landmarkObservation.landmarks
        let bbox = landmarkObservation.boundingBox

        // 头部姿态：优先取 poseObservation，其次取缓存
        let roll = poseObservation?.roll?.floatValue ?? cachedRoll
        let pitch = poseObservation?.pitch?.floatValue ?? cachedPitch
        let yaw = poseObservation?.yaw?.floatValue ?? cachedYaw

        // 眼睑轮廓
        let leftEye = Self.landmarkPoints(from: landmarks?.leftEye, in: bbox)
        let rightEye = Self.landmarkPoints(from: landmarks?.rightEye, in: bbox)

        // 瞳孔（每个区域只有一个点）
        let leftPupil = Self.landmarkPoints(from: landmarks?.leftPupil, in: bbox)?.first
        let rightPupil = Self.landmarkPoints(from: landmarks?.rightPupil, in: bbox)?.first

        // 嘴唇（保持归一化坐标，不转换为绝对坐标）
        let outerLips = landmarks?.outerLips?.normalizedPoints
        let innerLips = landmarks?.innerLips?.normalizedPoints

        // 新增绝对坐标版本
        let outerLipsAbsolute = Self.landmarkPoints(from: landmarks?.outerLips, in: bbox)
        let innerLipsAbsolute = Self.landmarkPoints(from: landmarks?.innerLips, in: bbox)

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
            outerLipsAbsolute: outerLipsAbsolute,
            innerLipsAbsolute: innerLipsAbsolute,
            faceContour: faceContour
        )
    }
}
