import CoreGraphics

class CursorController {
    /// 指尖屏幕坐标（已通过灵敏度缩放）
    private var handTip: CGPoint?
    /// 头部偏移量（直接从面部欧拉角获得）
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0
    /// 是否启用了注视追踪
    private var gazeActive = false

    /// 更新指尖位置（屏幕坐标，已乘灵敏度）
    func updateHandTip(_ point: CGPoint) {
        handTip = point
    }

    /// 更新注视偏移（无灵敏度缩放，内部保留原始值）
    func updateGazeOffset(yaw: Float, pitch: Float) {
        yawOffset = yaw
        pitchOffset = pitch
        gazeActive = true
    }

    /// 重置注视追踪状态（当无面部时调用）
    func resetGaze() {
        gazeActive = false
    }

    /// 计算最终光标位置
    /// - Parameters:
    ///   - screenSize: 屏幕尺寸（点）
    ///   - sensitivity: 鼠标速度倍率（通常为 1.0，因为指尖已经乘以 config.mouseSensitivity）
    /// - Returns: 光标在屏幕上的绝对位置
    func computeCursor(screenSize: CGSize, sensitivity: Float) -> CGPoint {
        guard let tip = handTip else {
            return .zero
        }
        var cursor = tip
        if gazeActive {
            // 根据经验比例缩放头部偏移
            let yawDelta = CGFloat(yawOffset) * screenSize.width * 0.05
            let pitchDelta = CGFloat(pitchOffset) * screenSize.height * 0.05
            cursor.x += yawDelta
            cursor.y += pitchDelta
        }
        // 限制在屏幕内
        cursor.x = max(0, min(cursor.x, screenSize.width))
        cursor.y = max(0, min(cursor.y, screenSize.height))
        return cursor
    }
}
