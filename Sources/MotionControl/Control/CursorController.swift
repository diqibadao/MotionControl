import CoreGraphics

class CursorController {
    /// 指尖屏幕坐标（已通过灵敏度缩放）
    private var handTip: CGPoint?
    /// 头部偏移量（直接从面部欧拉角获得）
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0
    /// 是否启用了注视追踪
    private var gazeActive = false

    /// 上一次平滑后的光标位置（用于防抖）
    private var lastSmoothedCursor: CGPoint?

    /// 更新指尖位置（屏幕坐标，已乘灵敏度）
    func updateHandTip(_ point: CGPoint) {
        handTip = point
    }

    /// 更新注视偏移（无灵敏度缩放，内部保留原始值）
    func updateGazeOffset(yaw: Float, pitch: Float, hasFace: Bool) {
        yawOffset = yaw
        pitchOffset = pitch
        gazeActive = hasFace
    }

    /// 重置注视追踪状态（当无面部时调用）
    func resetGaze() {
        gazeActive = false
    }

    /// 重置光标防抖状态（当需要强制重新定位时调用，比如切换输入源）
    func resetCursor() {
        lastSmoothedCursor = nil
    }

    /// 计算最终光标位置
    /// - Parameters:
    ///   - screenSize: 屏幕尺寸（点）
    ///   - sensitivity: 鼠标速度倍率（通常为 1.0，因为指尖已经乘以 config.mouseSensitivity）
    /// - Returns: 光标在屏幕上的绝对位置
    func computeCursor(screenSize: CGSize, sensitivity: Float) -> CGPoint {
        guard let tip = handTip else {
            return lastSmoothedCursor ?? .zero
        }
        // 1. 基础位置：指尖位置
        var raw = tip
        if gazeActive {
            // 根据经验比例缩放头部偏移
            let yawDelta = CGFloat(yawOffset) * screenSize.width * 0.05
            let pitchDelta = CGFloat(pitchOffset) * screenSize.height * 0.05
            raw.x += yawDelta
            raw.y += pitchDelta
        }
        // 2. 限制在屏幕内
        raw.x = max(0, min(raw.x, screenSize.width))
        raw.y = max(0, min(raw.y, screenSize.height))

        // 3. 防抖处理（指数平滑 + 跳跃抑制）
        guard let prev = lastSmoothedCursor else {
            // 首次：直接使用原始位置作为平滑位置
            lastSmoothedCursor = raw
            return raw
        }

        let dx = raw.x - prev.x
        let dy = raw.y - prev.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance < 2.0 {
            // 小位移 → 返回上次位置（忽略抖动）
            return prev
        }

        // 指数平滑：new = prev * 0.7 + raw * 0.3
        var smoothed = CGPoint(
            x: prev.x * 0.7 + raw.x * 0.3,
            y: prev.y * 0.7 + raw.y * 0.3
        )
        // 再次限制避免平滑后超出边界
        smoothed.x = max(0, min(smoothed.x, screenSize.width))
        smoothed.y = max(0, min(smoothed.y, screenSize.height))

        lastSmoothedCursor = smoothed
        return smoothed
    }
}
