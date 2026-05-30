import CoreGraphics
import Foundation

class CursorController {

    // MARK: - 属性

    /// 当前光标位置（未经注视偏移的平滑位置）
    var currentPosition: CGPoint = .zero

    /// EMA 平滑因子，数值越大平滑效果越强
    var smoothingFactor: CGFloat = 7

    /// 手指是否激活（方向控制模式）
    private(set) var fingerActive = false

    /// 头部偏移量（直接从面部欧拉角获得）
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0

    /// 是否启用了注视追踪
    private var gazeActive = false

    /// UI 元素扫描器（用于磁性吸引）
    var uiScanner: UIElementScanner? = nil

    // MARK: - 公开方法

    /// 更新手指指向的目标位置，并用自适应平滑移动到该位置
    func updateTargetPosition(_ target: CGPoint) {
        let diff = CGPoint(x: target.x - currentPosition.x,
                           y: target.y - currentPosition.y)
        let distance = sqrt(diff.x * diff.x + diff.y * diff.y)
        let factor: CGFloat = distance > 100 ? 4 : 8
        currentPosition.x += diff.x / factor
        currentPosition.y += diff.y / factor
        fingerActive = true
    }

    /// 更新注视偏移
    func updateGazeOffset(yaw: Float, pitch: Float, hasFace: Bool) {
        yawOffset = yaw
        pitchOffset = pitch
        gazeActive = hasFace
    }

    /// 重置注视追踪状态
    func resetGaze() {
        gazeActive = false
    }

    /// 重置光标状态（仅重置手指激活）
    func resetCursor() {
        fingerActive = false
    }

    // MARK: - 光标计算

    /// 计算最终光标位置（加入注视偏移并限制在屏幕范围内）
    func computeCursor(screenSize: CGSize, sensitivity: Float, dt: Double = 1.0 / 30.0) -> CGPoint {
        var cursor = currentPosition

        // 磁性吸引：吸附到最近的 UI 元素
        if let scanner = uiScanner {
            var nearestDist: CGFloat = 80
            var nearestCenter: CGPoint? = nil
            for element in scanner.elements {
                let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                let dx = center.x - cursor.x
                let dy = center.y - cursor.y
                let distance = sqrt(dx * dx + dy * dy)
                if distance < nearestDist {
                    nearestDist = distance
                    nearestCenter = center
                }
            }
            if let center = nearestCenter {
                let pull = (80 - nearestDist) / 80
                let strength: CGFloat = 0.15
                cursor.x += (center.x - cursor.x) * pull * strength
                cursor.y += (center.y - cursor.y) * pull * strength
            }
        }

        // 加入注视偏移
        if gazeActive {
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
