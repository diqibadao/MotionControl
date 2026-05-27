import CoreGraphics

/// 根据面部检测结果（头部姿态与瞳孔位置）估算用户注视屏幕的位置。
public struct GazePoint {
    public let screenPosition: CGPoint
    public let confidence: Float
    public let rawPosition: CGPoint

    public init(screenPosition: CGPoint, confidence: Float, rawPosition: CGPoint) {
        self.screenPosition = screenPosition
        self.confidence = confidence
        self.rawPosition = rawPosition
    }
}

public class GazeEstimator {
    /// 指数平滑因子（0~1），值越大对新数据响应越快。
    public var smoothFactor: Float = 0.3

    private var smoothedRawPosition: CGPoint?

    public init() {}

    /// 估算注视点。
    /// - Parameters:
    ///   - face: 面部检测结果，需包含 `yaw`、`pitch` 等欧拉角，以及左右瞳孔的归一化坐标。
    ///   - screenSize: 屏幕尺寸（点）。
    /// - Returns: 包含屏幕坐标、置信度和原始坐标的 `GazePoint`。
    public func estimate(from face: FaceResult, screenSize: CGSize) -> GazePoint {
        // 1. 检查方向数据
        guard let yaw = face.yaw,
              let pitch = face.pitch else {
            // 无有效方向时，返回上次平滑位置（若存在），否则返回原点，置信度为 0
            if let smoothed = smoothedRawPosition {
                return GazePoint(
                    screenPosition: CGPoint(x: smoothed.x * screenSize.width,
                                            y: smoothed.y * screenSize.height),
                    confidence: 0,
                    rawPosition: .zero
                )
            } else {
                return GazePoint(screenPosition: .zero, confidence: 0, rawPosition: .zero)
            }
        }

        // 2. 基于头部姿态计算原始归一化坐标 [0,1]
        let maxAngle: Float = 0.5
        var rawX = CGFloat((yaw / maxAngle) * 0.5 + 0.5)
        var rawY = CGFloat((pitch / maxAngle) * (-0.5) + 0.5)
        rawX = min(max(rawX, 0), 1)
        rawY = min(max(rawY, 0), 1)
        var rawNormalized = CGPoint(x: rawX, y: rawY)

        // 3. 利用瞳孔位置进行微调（若有双眼数据）
        let hasPupils = face.leftPupil != nil && face.rightPupil != nil
        if let leftPupil = face.leftPupil,
           let rightPupil = face.rightPupil {
            let eyeCenter = CGPoint(x: (leftPupil.x + rightPupil.x) / 2,
                                    y: (leftPupil.y + rightPupil.y) / 2)
            let gazeOffset = CGPoint(x: (eyeCenter.x - 0.5) * 0.2,
                                     y: (eyeCenter.y - 0.5) * 0.2)
            rawNormalized.x += gazeOffset.x
            rawNormalized.y += gazeOffset.y
            rawNormalized.x = min(max(rawNormalized.x, 0), 1)
            rawNormalized.y = min(max(rawNormalized.y, 0), 1)
        }

        // 4. 指数平滑
        if let smoothed = smoothedRawPosition {
            let factor = CGFloat(smoothFactor)
            smoothedRawPosition = CGPoint(
                x: smoothed.x * (1 - factor) + rawNormalized.x * factor,
                y: smoothed.y * (1 - factor) + rawNormalized.y * factor
            )
        } else {
            smoothedRawPosition = rawNormalized
        }

        let smoothedPos = smoothedRawPosition!
        let screenPos = CGPoint(x: smoothedPos.x * screenSize.width,
                                y: smoothedPos.y * screenSize.height)
        let rawScreenPos = CGPoint(x: rawNormalized.x * screenSize.width,
                                   y: rawNormalized.y * screenSize.height)

        // 5. 置信度：有瞳孔数据时 0.8，否则 0.5
        let confidence: Float = hasPupils ? 0.8 : 0.5

        return GazePoint(screenPosition: screenPos, confidence: confidence, rawPosition: rawScreenPos)
    }
}
