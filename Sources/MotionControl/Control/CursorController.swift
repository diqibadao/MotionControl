import CoreGraphics

class CursorController {
    /// 计算光标位置
    /// - Parameters:
    ///   - indexTip: 指尖归一化坐标 (0~1)
    ///   - yawOffset: 头部偏航偏移
    ///   - pitchOffset: 头部俯仰偏移
    ///   - gazeEnabled: 是否开启视线融合
    ///   - mouseSpeed: 鼠标速度倍率
    ///   - gazeSensitivity: 视线灵敏度
    ///   - screenSize: 屏幕尺寸（点）
    /// - Returns: 光标在屏幕上的绝对位置
    func computeCursor(
        indexTip: CGPoint,
        yawOffset: Float,
        pitchOffset: Float,
        gazeEnabled: Bool,
        mouseSpeed: Float,
        gazeSensitivity: Float,
        screenSize: CGSize
    ) -> CGPoint {
        if !gazeEnabled {
            // 纯手指模式
            let x = indexTip.x * screenSize.width * CGFloat(mouseSpeed)
            let y = indexTip.y * screenSize.height * CGFloat(mouseSpeed)
            return CGPoint(x: x, y: y)
        } else {
            // 融合模式：指尖 + 头部偏移，并限制在 0~1 之间
            let offsetX = CGFloat(yawOffset) * CGFloat(gazeSensitivity) * 0.2
            let offsetY = CGFloat(pitchOffset) * CGFloat(gazeSensitivity) * 0.2
            var tipX = indexTip.x + offsetX
            var tipY = indexTip.y + offsetY
            tipX = min(max(tipX, 0), 1)
            tipY = min(max(tipY, 0), 1)
            let x = tipX * screenSize.width * CGFloat(mouseSpeed)
            let y = tipY * screenSize.height * CGFloat(mouseSpeed)
            return CGPoint(x: x, y: y)
        }
    }
}
