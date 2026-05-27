//
//  GazeEstimator.swift
//  MotionControl
//

import CoreGraphics

/// 注视估算结果（偏移量，不包含屏幕坐标）。
struct GazeEstimate {
    let yawOffset: Float
    let pitchOffset: Float
    let hasFace: Bool
}

/// 注视估算器，使用 actor 保证线程安全。
actor GazeEstimator {
    /// 指数平滑因子（0～1），值越大对新数据响应越快。
    var smoothFactor: Float = 0.3

    // MARK: - 校准相关状态
    private var isCalibrating = false
    private var calibratingFrameCount = 0
    private var sumYaw: Float = 0
    private var sumPitch: Float = 0
    private var baselineYaw: Float?
    private var baselinePitch: Float?
    private let calibrationFramesRequired = 30

    // MARK: - 平滑偏移状态
    private var smoothedYawOffset: Float?
    private var smoothedPitchOffset: Float?

    init() {}

    /// 启动自动校准：重置所有累计数据，收集接下来 30 帧的头部角度均值作为 baseline。
    func autoCalibrate() {
        isCalibrating = true
        calibratingFrameCount = 0
        sumYaw = 0
        sumPitch = 0
        baselineYaw = nil
        baselinePitch = nil
    }

    /// 估算注视偏移量。
    /// - Parameter face: 面部检测结果，需包含 `yaw`、`pitch` 等欧拉角。
    /// - Returns: 包含偏移量和平稳值的 `GazeEstimate` 结构体。
    func estimate(from face: FaceResult) -> GazeEstimate {
        let inputStr = "yaw=\(face.yaw?.description ?? "nil") pitch=\(face.pitch?.description ?? "nil")"

        // 1. 检查方向数据
        guard let yaw = face.yaw,
              let pitch = face.pitch else {
            // 无有效方向时，返回平滑后的偏移（若存在），否则返回 0；hasFace = false
            let outputStr = "yawOffset=\(smoothedYawOffset ?? 0) pitchOffset=\(smoothedPitchOffset ?? 0) hasFace=false"
            EventLogger.log(event: "gaze_estimate",
                            frame: nil,
                            input: inputStr,
                            output: outputStr,
                            duration: nil)
            return GazeEstimate(
                yawOffset: smoothedYawOffset ?? 0,
                pitchOffset: smoothedPitchOffset ?? 0,
                hasFace: false
            )
        }

        // 2. 处理校准
        if isCalibrating && calibratingFrameCount < calibrationFramesRequired {
            sumYaw += yaw
            sumPitch += pitch
            calibratingFrameCount += 1
            if calibratingFrameCount == calibrationFramesRequired {
                baselineYaw = sumYaw / Float(calibratingFrameCount)
                baselinePitch = sumPitch / Float(calibratingFrameCount)
                isCalibrating = false
            }
            // 校准期间偏移为 0（baseline 尚未确定）
            let (smoothYaw, smoothPitch) = applySmoothing(rawYaw: 0, rawPitch: 0)
            let outputStr = "yawOffset=\(smoothYaw) pitchOffset=\(smoothPitch) hasFace=true"
            EventLogger.log(event: "gaze_estimate",
                            frame: nil,
                            input: inputStr,
                            output: outputStr,
                            duration: nil)
            return GazeEstimate(
                yawOffset: smoothYaw,
                pitchOffset: smoothPitch,
                hasFace: true
            )
        }

        // 3. 正常计算偏移（减去 baseline）
        let rawYawOffset = yaw - (baselineYaw ?? 0)
        let rawPitchOffset = pitch - (baselinePitch ?? 0)

        let (smoothYaw, smoothPitch) = applySmoothing(rawYaw: rawYawOffset, rawPitch: rawPitchOffset)

        let outputStr = "yawOffset=\(smoothYaw) pitchOffset=\(smoothPitch) hasFace=true"
        EventLogger.log(event: "gaze_estimate",
                        frame: nil,
                        input: inputStr,
                        output: outputStr,
                        duration: nil)

        return GazeEstimate(
            yawOffset: smoothYaw,
            pitchOffset: smoothPitch,
            hasFace: true
        )
    }

    // MARK: - 内部平滑辅助
    private func applySmoothing(rawYaw: Float, rawPitch: Float) -> (Float, Float) {
        let factor = CGFloat(smoothFactor)
        let oneMinusFactor = CGFloat(1.0) - factor

        let newYaw: Float
        let newPitch: Float

        if let smoothedYaw = smoothedYawOffset {
            newYaw = Float(CGFloat(smoothedYaw) * oneMinusFactor + CGFloat(rawYaw) * factor)
        } else {
            newYaw = rawYaw
        }

        if let smoothedPitch = smoothedPitchOffset {
            newPitch = Float(CGFloat(smoothedPitch) * oneMinusFactor + CGFloat(rawPitch) * factor)
        } else {
            newPitch = rawPitch
        }

        smoothedYawOffset = newYaw
        smoothedPitchOffset = newPitch

        return (newYaw, newPitch)
    }
}
