import CoreGraphics
import Foundation

class CursorController {

    // MARK: - 嵌套自适应滤波类
    private class OneEuroFilter {
        private let minCutoff: Double
        private let beta: Double
        private var prevRawX: Double?
        private var prevRawY: Double?
        private var prevFilteredX: Double?
        private var prevFilteredY: Double?

        init(minCutoff: Double = 3.0, beta: Double = 0.02) {
            self.minCutoff = minCutoff
            self.beta = beta
        }

        /// 对 (x,y) 二维量进行滤波，返回滤波后的 CGPoint
        func filter(x: Double, y: Double, dt: Double = 1.0 / 30.0) -> CGPoint {
            guard let pfx = prevFilteredX,
                  let pfy = prevFilteredY,
                  let prx = prevRawX,
                  let pry = prevRawY else {
                // 首次：直接通过
                prevRawX = x; prevRawY = y
                prevFilteredX = x; prevFilteredY = y
                return CGPoint(x: x, y: y)
            }

            // 导数（变化率）
            let dValueX = abs((x - prx) / dt)
            let dValueY = abs((y - pry) / dt)

            let cutoffX = minCutoff + beta * dValueX
            let cutoffY = minCutoff + beta * dValueY

            let alphaX = 1.0 / (1.0 + dt * cutoffX)
            let alphaY = 1.0 / (1.0 + dt * cutoffY)

            let smoothX = alphaX * x + (1.0 - alphaX) * pfx
            let smoothY = alphaY * y + (1.0 - alphaY) * pfy

            prevRawX = x; prevRawY = y
            prevFilteredX = smoothX; prevFilteredY = smoothY

            return CGPoint(x: smoothX, y: smoothY)
        }

        /// 重置滤波状态
        func reset() {
            prevRawX = nil
            prevRawY = nil
            prevFilteredX = nil
            prevFilteredY = nil
        }
    }

    // MARK: - 属性

    /// 指尖屏幕坐标（保留以兼容原有接口，但不再用于光标计算）
    private var handTip: CGPoint?

    /// 头部偏移量（直接从面部欧拉角获得）
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0

    /// 是否启用了注视追踪
    private var gazeActive = false

    /// 手指是否激活（方向控制模式）
    private(set) var fingerActive = false

    /// 滤波后的方向速度（屏幕坐标/秒）
    private var filteredVelocity: CGPoint = .zero

    /// 当前基座光标位置（不含注视偏移）
    private var baseCursor: CGPoint = .zero

    /// 自适应低通滤波器
    private let fingerFilter = OneEuroFilter()

    // MARK: - 公开方法

    /// 更新指尖位置（屏幕坐标，已乘灵敏度）
    func updateHandTip(_ point: CGPoint) {
        handTip = point
        // 当有指尖点时可选将 fingerActive 置为 true，但方向控制模式主要依赖 updateFingerDirection
        // 这里仅保留原有赋值
    }

    /// 更新注视偏移（无灵敏度缩放）
    func updateGazeOffset(yaw: Float, pitch: Float, hasFace: Bool) {
        yawOffset = yaw
        pitchOffset = pitch
        gazeActive = hasFace
    }

    /// 重置注视追踪状态
    func resetGaze() {
        gazeActive = false
    }

    /// 重置光标状态（包括基座位置、滤波状态、手指激活）
    func resetCursor() {
        baseCursor = .zero
        filteredVelocity = .zero
        fingerActive = false
        fingerFilter.reset()
    }

    // MARK: - 新增方法：方向速度映射

    /// 更新手指方向速度并进行自适应低通滤波
    /// - Parameters:
    ///   - direction: 手指移动方向（归一化向量）
    ///   - length: 方向上未缩放的长度（如原始移动量）
    ///   - sensitivity: 灵敏度倍率
    func updateFingerDirection(_ direction: CGPoint, length: CGFloat, sensitivity: CGFloat) {
        let rawVx = Double(direction.x * length * sensitivity)
        let rawVy = Double(direction.y * length * sensitivity)

        let filtered = fingerFilter.filter(x: rawVx, y: rawVy, dt: 1.0 / 30.0)
        filteredVelocity = filtered
        fingerActive = true
    }

    // MARK: - 光标计算（增量模式）

    /// 计算最终光标位置
    /// - Parameters:
    ///   - screenSize: 屏幕尺寸（点）
    ///   - sensitivity: 未使用（保留签名一致）
    /// - Returns: 光标在屏幕上的绝对位置
    func computeCursor(screenSize: CGSize, sensitivity: Float) -> CGPoint {
        // 1. 基础位置（不含注视偏移）
        var newBase = baseCursor
        if fingerActive {
            let dt: CGFloat = 1.0 / 30.0
            newBase.x += CGFloat(filteredVelocity.x) * dt
            newBase.y += CGFloat(filteredVelocity.y) * dt
        }

        // 2. 增加注视偏移
        var cursor = newBase
        if gazeActive {
            let yawDelta = CGFloat(yawOffset) * screenSize.width * 0.05
            let pitchDelta = CGFloat(pitchOffset) * screenSize.height * 0.05
            cursor.x += yawDelta
            cursor.y += pitchDelta
        }

        // 3. 限制在屏幕内
        cursor.x = max(0, min(cursor.x, screenSize.width))
        cursor.y = max(0, min(cursor.y, screenSize.height))

        // 4. 存储基座（不含注视偏移）
        baseCursor = newBase

        return cursor
    }
}
