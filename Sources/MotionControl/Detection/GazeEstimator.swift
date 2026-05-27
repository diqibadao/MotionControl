import CoreGraphics

/// 根据面部检测结果（头部姿态与瞳孔位置）估算用户注视屏幕的位置。
public class GazeEstimator {
    public init() {}

    /// 估算注视点。
    /// - Parameters:
    ///   - faceResult: 面部检测结果，需包含 `yaw`、`pitch` 等欧拉角，以及左右瞳孔的归一化坐标。
    ///   - screenSize: 屏幕尺寸（点）。
    /// - Returns: 屏幕上的注视点坐标，若无法估算则返回 `nil`。
    public func estimateGaze(from faceResult: FaceResult, screenSize: CGSize) -> CGPoint? {
        // 1. 基于头部姿态获得粗略注视方向
        guard let yaw = faceResult.yaw?.doubleValue,
              let pitch = faceResult.pitch?.doubleValue else {
            return nil
        }

        // 假设 yaw 范围 ±0.5 rad，pitch 范围 ±0.5 rad（可根据实际校准调整）
        let maxAngle: Double = 0.5
        // 将角度映射到屏幕归一化坐标 [0, 1]
        var x = CGFloat((yaw / maxAngle) * 0.5 + 0.5)
        var y = CGFloat((pitch / maxAngle) * (-0.5) + 0.5)   // pitch 为正时头部上扬，注视点应上移
        x = min(max(x, 0), 1)
        y = min(max(y, 0), 1)

        // 2. 使用瞳孔位置进行微调（若有数据）
        if let leftPupil = faceResult.leftPupil,
           let rightPupil = faceResult.rightPupil {
            // 计算双眼中心归一化坐标 (图像坐标系 0~1, 左上为原点)
            let eyeCenter = CGPoint(x: (leftPupil.x + rightPupil.x) / 2,
                                    y: (leftPupil.y + rightPupil.y) / 2)
            // 将眼球中心偏移映射为屏幕注视偏移（缩放因子 0.2 仅为示例，实际需校准）
            let gazeOffset = CGPoint(x: (eyeCenter.x - 0.5) * 0.2,
                                     y: (eyeCenter.y - 0.5) * 0.2)
            x += gazeOffset.x
            y += gazeOffset.y
            x = min(max(x, 0), 1)
            y = min(max(y, 0), 1)
        }

        // 转换为屏幕坐标
        return CGPoint(x: x * screenSize.width, y: y * screenSize.height)
    }
}
