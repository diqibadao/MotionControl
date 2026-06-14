import CoreGraphics
import Foundation
import AppKit

// MARK: - 1€ Filter（One Euro Filter）
/// CHI 2012, Casiez et al. — 自适应低通滤波器，专为带噪声的实时交互信号设计。
/// Meta Quest / OpenXR 手部跟踪同款算法。
/// 速度自适应当前只用 EMA + Lerp + 死区 + 增益曲线 4 层叠加。
struct OneEuroFilter {
    private let fcMin: CGFloat      // 最小截频 Hz，控制静止时平滑度
    private let beta: CGFloat       // 速度系数，控制响应速度
    private let fcD: CGFloat        // 微分截频 Hz

    private var prevX: CGFloat = 0
    private var prevDx: CGFloat = 0
    private var prevTime: TimeInterval = 0
    private var initialized = false

    init(fcMin: CGFloat = 1.0, beta: CGFloat = 0.007, fcD: CGFloat = 1.0) {
        self.fcMin = fcMin
        self.beta = beta
        self.fcD = fcD
    }

    /// 滤波一个值，返回平滑后的值
    mutating func filter(_ x: CGFloat, time: TimeInterval) -> CGFloat {
        guard initialized else {
            prevX = x
            prevDx = 0
            prevTime = time
            initialized = true
            return x
        }

        let dt = max(CGFloat(time - prevTime), 1e-6)  // 防除零
        prevTime = time

        // 1. 计算导数（信号变化速度）
        let dx = (x - prevX) / dt

        // 2. 对导数做低通滤波（固定截频 fcD）
        let alphaD = smoothingFactor(fc: fcD, dt: dt)
        prevDx = prevDx + alphaD * (dx - prevDx)

        // 3. 自适应截频：速度快→截频高→滤波弱
        let fc = fcMin + beta * abs(prevDx)

        // 4. 用自适应截频对原始信号做低通
        let alpha = smoothingFactor(fc: fc, dt: dt)
        prevX = prevX + alpha * (x - prevX)

        return prevX
    }

    /// 重置滤波器状态
    mutating func reset() {
        initialized = false
        prevX = 0
        prevDx = 0
        prevTime = 0
    }

    private func smoothingFactor(fc: CGFloat, dt: CGFloat) -> CGFloat {
        let tau = 1.0 / (2.0 * CGFloat.pi * fc)
        return dt / (dt + tau)
    }
}

class CursorController {

    // MARK: - 固定原点和边界盒子

    /// 静止原点（归一化坐标，0~1），手在此位置时光标在屏幕中间
    /// 固定不变（Leap Motion InteractionBox 方案），不动态校准
    let origin: CGPoint = CGPoint(x: 0.5, y: 0.4)

    /// 边缘逃逸：上帧手位，用于检测边缘处的手方向反转
    private var prevHandX: CGFloat = 0.5
    private var prevHandY: CGFloat = 0.4

    // MARK: - 属性

    /// 当前光标位置（未经注视偏移的平滑位置）
    var currentPosition: CGPoint = .zero
    /// 检测帧设定的目标位置，60fps 定时器持续 Lerp 追赶
    var targetPosition: CGPoint = .zero

    /// 手指是否激活（方向控制模式）
    private(set) var fingerActive = false

    /// Velocity EMA 平滑
    private var smoothVx: CGFloat = 0
    private var smoothVy: CGFloat = 0
    private let velocityEMAAlpha: CGFloat = 0.5
    private var lastUpdateTime: Date = .distantPast

    /// 60fps 补帧用的 velocity（只读，由 updateWithDelta 更新）
    var displayVelocityX: CGFloat { smoothVx }
    var displayVelocityY: CGFloat { smoothVy }

    /// 头部偏移量（直接从面部欧拉角获得）
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0

    /// 是否启用了注视追踪
    private var gazeActive = false

    /// UI 元素扫描器（用于力场磁吸）
    var uiScanner: UIElementScanner? = nil

    /// 沙坑粘滞状态（Stickiness Sandpit）：光标在按钮上减速而非被拉拽
    enum StickinessState {
        case free                          // 无跟踪元素
        case tracking(UIElementInfo)       // 正跟踪此元素，对其施加粘滞减速

        var isTracking: Bool {
            if case .tracking = self { return true }
            return false
        }
    }
    private var stickinessState: StickinessState = .free
    /// 缓存被跟踪元素的中心坐标，避免帧间重复计算
    private var trackedElementCenter: CGPoint = .zero
    /// 上次元素切换时间（用于冷却期控制）
    private var lastElementSwitchTime: TimeInterval = 0
    /// 切换冷却期（秒）
    private let elementSwitchCooldown: TimeInterval = 0.2

    // MARK: - 公开方法

    /// 更新光标位置（基于指尖位移）
    /// - Parameters:
    ///   - tip: 当前帧指尖归一化坐标 (0~1)
    ///   - lastTip: 上一帧指尖归一化坐标
    ///   - screenSize: 屏幕尺寸
    ///   - sensitivity: 灵敏度倍率
    ///   - dt: 两帧之间的时间间隔（秒），用于速度自适应
    func updateWithDelta(tip: CGPoint, lastTip: CGPoint, screenSize: CGSize, sensitivity: Float, dt: TimeInterval = 1.0/15.0) {
        lastUpdateTime = Date()  // 重置衰减计时，避免定时器衰减打架

        let rawDx = (lastTip.x - tip.x)
        let rawDy = (tip.y - lastTip.y)

        // 灵敏度基于参考分辨率 1920×1080 归一化，不再直接乘屏幕分辨率。
        // 之前用 screenSize.width/height 直接乘，导致换大屏后灵敏度被等比放大
        // （4K 屏上是内置屏的 2.6 倍），光标线性度完全丧失。
        let refWidth: CGFloat = 1920
        let refHeight: CGFloat = 1080
        let dx = rawDx * refWidth * CGFloat(sensitivity)
        let dy = rawDy * refHeight * CGFloat(sensitivity)

        // 固定时间基准 30fps，速度和位移使用同一个 dt，帧率无关
        let frameDt: TimeInterval = 1.0 / 30.0
        let rawVx = dx / CGFloat(frameDt)
        let rawVy = dy / CGFloat(frameDt)
        let newSmoothVx = velocityEMAAlpha * rawVx + (1 - velocityEMAAlpha) * smoothVx
        let newSmoothVy = velocityEMAAlpha * rawVy + (1 - velocityEMAAlpha) * smoothVy

        // 方向反转检测：和旧速度比（不是 blended 值），避免漏判
        if rawVx * smoothVx < 0 { smoothVx = newSmoothVx * 0.5 }
        else { smoothVx = newSmoothVx }
        if rawVy * smoothVy < 0 { smoothVy = newSmoothVy * 0.5 }
        else { smoothVy = newSmoothVy }

        let smoothDx = smoothVx * CGFloat(frameDt)
        let smoothDy = smoothVy * CGFloat(frameDt)

        let velocity = sqrt(smoothVx*smoothVx + smoothVy*smoothVy)

        // 平缓加速度曲线：0.5~3.5x
        let normalizedV = min(velocity / 300.0, 5.0)
        let factor: CGFloat = 0.5 + 2.0 * pow(normalizedV, 0.4)
        // v=0→0.5, v=150→1.9, v=300→2.5, v=500→3.0, v=1500→3.5

        let stepDx = smoothDx * factor
        let stepDy = smoothDy * factor

        // 单帧步长上限 150px
        let maxStep: CGFloat = 150
        let clampedDx = max(-maxStep, min(maxStep, stepDx))
        let clampedDy = max(-maxStep, min(maxStep, stepDy))

        currentPosition.x += clampedDx
        currentPosition.y += clampedDy

        currentPosition.x = max(0, min(currentPosition.x, screenSize.width))
        currentPosition.y = max(0, min(currentPosition.y, screenSize.height))

#if DEBUG
        print("[CURSOR] raw=(\(String(format:"%.4f",rawDx)),\(String(format:"%.4f",rawDy))) dx=(\(String(format:"%.0f",dx)),\(String(format:"%.0f",dy))) v=(\(String(format:"%.0f",velocity))) factor=\(String(format:"%.2f",factor)) step=(\(String(format:"%.0f",clampedDx)),\(String(format:"%.0f",clampedDy))) pos=(\(String(format:"%.0f",currentPosition.x)),\(String(format:"%.0f",currentPosition.y)))")
#endif

        fingerActive = true
    }

    // MARK: - 绝对位置映射

    /// 1€ Filter — 自适应低通滤波器，替代 EMA+Lerp+死区+增益曲线
    private var filterX = OneEuroFilter(fcMin: 1.2, beta: 0.05, fcD: 1.0)
    private var filterY = OneEuroFilter(fcMin: 1.2, beta: 0.05, fcD: 1.0)
    private var filterTimeBase: TimeInterval = 0

    // MARK: - 帧丢失保护（Temporal Gap Guard）
    /// UmeTrack (Meta, SIGGRAPH 2022) 方案：检测帧间隔异常 → 预测平滑，避免光标跳变
    private var prevUpdateTime: TimeInterval = 0
    private var prevTarget: CGPoint = .zero
    private var screenVelocityX: CGFloat = 0
    private var screenVelocityY: CGFloat = 0
    private var gapRecoveryUntil: TimeInterval = 0
    private let gapThreshold: TimeInterval = 0.2        // >200ms 视为帧丢失
    private let gapRecoveryWindow: TimeInterval = 0.3   // 300ms 内从预测收敛到真实目标

    /// 手进入画面时重置滤波器，光标从当前位置开始
    func handAppeared() {
        filterX.reset()
        filterY.reset()
        filterTimeBase = 0
        fingerActive = true
        prevUpdateTime = 0
        prevTarget = .zero
        screenVelocityX = 0
        screenVelocityY = 0
        gapRecoveryUntil = 0
        if currentPosition == .zero {
            let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
            currentPosition = CGPoint(x: screen.width / 2, y: screen.height / 2)
        }
    }

    /// 手离开画面时重置
    func handDisappeared() {
        filterX.reset()
        filterY.reset()
        filterTimeBase = 0
        fingerActive = false
        prevUpdateTime = 0
        prevTarget = .zero
        screenVelocityX = 0
        screenVelocityY = 0
        gapRecoveryUntil = 0
        stickinessState = .free
        uiScanner?.unlockElement()
    }
    func updateWithAbsolutePosition(
        handCenter: CGPoint,
        screenSize: CGSize,
        gain: Float = 2.0,
        handedness: HandSide = .unknown
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        if filterTimeBase == 0 { filterTimeBase = now }
        let t = now - filterTimeBase

        // 1€ Filter 自适应平滑：手静止→强滤震颤，手快→轻滤跟手
        // 边缘逃逸：光标贴边且手往回拉 → 跳过 filter，直接用 raw handCenter
        let escapingLeft  = targetPosition.x <= 1 && handCenter.x < prevHandX
        let escapingRight = targetPosition.x >= screenSize.width - 1 && handCenter.x > prevHandX
        let escapingTop    = targetPosition.y <= 1 && handCenter.y > prevHandY
        let escapingBottom = targetPosition.y >= screenSize.height - 1 && handCenter.y < prevHandY

        if escapingLeft || escapingRight {
            filterX.reset()
            _ = filterX.filter(handCenter.x, time: t)
        }
        if escapingTop || escapingBottom {
            filterY.reset()
            _ = filterY.filter(handCenter.y, time: t)
        }

        let fx = filterX.filter(handCenter.x, time: t)
        let fy = filterY.filter(handCenter.y, time: t)
        prevHandX = handCenter.x
        prevHandY = handCenter.y

        // 偏移 = 滤波后手位置 - 原点
        let rawOffsetX = fx - origin.x
        let rawOffsetY = fy - origin.y

        // 原点校准自适应左右手差异（右手原点≈0.3, 左手原点≈0.7）
        // 摄像头镜像下，手物理右移 → 摄像头X减小 → rawOffsetX<0
        // cursorX = screenCX - offsetX * W * G，负offsetX → 光标右移 ✓
        // 左右手在镜像下均符合此规律，无需区分翻转
        let offsetX = rawOffsetX
        let offsetY = rawOffsetY

        // 三区可变增益（Variable Absolute Mapping）
        // Interior: 手近原点 → 精控不变
        // Border:   手渐远 → 增益线性提升，触达屏幕边缘
        // Margin:   手极远 → 饱和，光标贴边不跳
        let distFromOrigin = sqrt(offsetX * offsetX + offsetY * offsetY)
        let gainMultiplier: CGFloat
        if distFromOrigin < 0.12 {
            gainMultiplier = 1.0                      // Interior: 跟手不变
        } else if distFromOrigin < 0.25 {
            let t = (distFromOrigin - 0.12) / 0.13    // Border: 1.0 → 1.3 线性
            gainMultiplier = 1.0 + t * 0.3
        } else {
            gainMultiplier = 1.3                       // Margin: 饱和 1.3x
        }

        // 绝对映射：屏幕中心 + 偏移 × 屏幕尺寸 × 增益
        let screenCX = screenSize.width / 2
        let screenCY = screenSize.height / 2

        let effectiveGain = CGFloat(gain) * gainMultiplier

        // offset 上限：光标刚好到屏幕边缘即止，不产生负值
        let maxOffsetX = screenCX / (screenSize.width * effectiveGain)
        let maxOffsetY = screenCY / (screenSize.height * effectiveGain)
        let clampedOffsetX = max(-maxOffsetX, min(offsetX, maxOffsetX))
        let clampedOffsetY = max(-maxOffsetY, min(offsetY, maxOffsetY))

        let cursorX = screenCX - clampedOffsetX * screenSize.width * effectiveGain
        let cursorY = screenCY + clampedOffsetY * screenSize.height * effectiveGain

        // 屏幕边界约束：坐标在屏幕范围内，手出盒子自动截断
        let clampedX = max(0, min(cursorX, screenSize.width))
        let clampedY = max(0, min(cursorY, screenSize.height))

        // 设定目标位置，120Hz 定时器 Lerp 追赶
        let rawTarget = CGPoint(x: clampedX, y: clampedY)

        // Temporal Gap Guard：帧间隔 >200ms → 用预测位置平滑过渡
        let dt = now - prevUpdateTime
        if prevUpdateTime > 0 {
            if dt < gapThreshold {
                // 正常帧：更新屏幕空间速度 EMA
                let rawVx = (rawTarget.x - prevTarget.x) / CGFloat(max(dt, 0.001))
                let rawVy = (rawTarget.y - prevTarget.y) / CGFloat(max(dt, 0.001))
                screenVelocityX = 0.5 * rawVx + 0.5 * screenVelocityX
                screenVelocityY = 0.5 * rawVy + 0.5 * screenVelocityY
                targetPosition = rawTarget
            } else {
                // 帧丢失：启动恢复窗口
                gapRecoveryUntil = now + gapRecoveryWindow
                targetPosition = rawTarget  // 先设目标，下面 blend 覆盖
            }
        } else {
            targetPosition = rawTarget
        }

        // 恢复窗口内：预测位置 → 真实目标 二次 ease-in 过渡
        if now < gapRecoveryUntil && prevUpdateTime > 0 {
            let elapsed = now - (gapRecoveryUntil - gapRecoveryWindow)
            let progress = CGFloat(max(0, min(1.0, elapsed / gapRecoveryWindow)))
            let blend = progress * progress  // ease-in quad: 0→1

            let predictedX = prevTarget.x + screenVelocityX * CGFloat(dt)
            let predictedY = prevTarget.y + screenVelocityY * CGFloat(dt)

            targetPosition.x = predictedX + (targetPosition.x - predictedX) * blend
            targetPosition.y = predictedY + (targetPosition.y - predictedY) * blend
        }

        prevTarget = targetPosition
        prevUpdateTime = now

        // L2: Voronoi 分区吸附 — 永远拉向最近按钮中心，距离衰减
        let cursorSpeed = sqrt(screenVelocityX * screenVelocityX + screenVelocityY * screenVelocityY)
        let assistConfig = ConfigManager.shared.currentConfig
        if assistConfig.assistEnabled && cursorSpeed < CGFloat(assistConfig.assistSpeedGate),
           let scanner = uiScanner, !scanner.cachedElements.isEmpty {
            let snapRange = CGFloat(assistConfig.assistSnapRange)
            let snapMax = CGFloat(assistConfig.assistSnapMax)
            let curvePower = CGFloat(assistConfig.assistSnapCurvePower)

            // IDW 引力场：只取最近的 K=5 个中心做加权混合（防远距离噪声星球稀释引力）
            let K = 5
            var nearest: [(CGFloat, CGPoint)] = []
            for el in scanner.cachedElements {
                let c = flippedCenter(of: el, screenSize: screenSize)
                let d = distance(from: c)
                if d < snapRange {
                    nearest.append((d, c))
                    nearest.sort { $0.0 < $1.0 }
                    if nearest.count > K { nearest.removeLast() }
                }
            }
            var totalWeight: CGFloat = 0
            var blendedCenter = CGPoint.zero
            for (d, c) in nearest {
                let t = d / snapRange
                let phi = pow(1.0 - t, 3.0)
                totalWeight += phi
                blendedCenter.x += c.x * phi
                blendedCenter.y += c.y * phi
            }

            guard totalWeight > 0 else { return }
            blendedCenter.x /= totalWeight
            blendedCenter.y /= totalWeight

            let blendedDist = distance(from: blendedCenter)
            let t = min(blendedDist / snapRange, 1.0)
            let strength = snapMax * pow(1.0 - t, curvePower)
            let bx = (blendedCenter.x - targetPosition.x) * strength
            let by = (blendedCenter.y - targetPosition.y) * strength
            targetPosition.x += bx
            targetPosition.y += by
            EventLogger.log(event: "SNAP", frame: nil,
                            input: "blend n=\(Int(totalWeight)) dist=\(Int(blendedDist)) t=\(String(format:"%.2f",t))",
                            output: "strength=\(String(format:"%.3f",strength)) bias=(\(Int(bx)),\(Int(by)))",
                            duration: nil)
        }

        // 沙坑粘滞：光标在按钮上时减速
        applyStickiness(screenSize: screenSize)

        lastUpdateTime = Date()
        fingerActive = true

        // 边界裁剪
        currentPosition.x = max(0, min(currentPosition.x, screenSize.width))
        currentPosition.y = max(0, min(currentPosition.y, screenSize.height))

#if DEBUG
        print("[CURSOR-ABS] handSide=\(handedness) hand=(\(String(format:"%.3f",handCenter.x)),\(String(format:"%.3f",handCenter.y))) filter=(\(String(format:"%.3f",fx)),\(String(format:"%.3f",fy))) target=(\(String(format:"%.0f",targetPosition.x)),\(String(format:"%.0f",targetPosition.y))) cursor=(\(String(format:"%.0f",currentPosition.x)),\(String(format:"%.0f",currentPosition.y)))")
#endif
        EventLogger.log(event: "CURSOR-ABS", frame: nil,
                        input: "handSide=\(handedness) hand=(\(String(format:"%.3f",handCenter.x)),\(String(format:"%.3f",handCenter.y))) filter=(\(String(format:"%.3f",fx)),\(String(format:"%.3f",fy)))",
                        output: "target=(\(String(format:"%.0f",targetPosition.x)),\(String(format:"%.0f",targetPosition.y))) cursor=(\(String(format:"%.0f",currentPosition.x)),\(String(format:"%.0f",currentPosition.y)))",
                        duration: nil)
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

    /// 重置光标状态（仅重置手指激活，力场状态复位）
    func resetCursor() {
        fingerActive = false
        stickinessState = .free
        uiScanner?.unlockElement()
    }

    /// 衰减速度（补帧定时器每帧调用）
    /// 仅在 updateWithDelta 超过 50ms 未调用时才衰减，避免和 EMA 更新打架
    func decayVelocity(by factor: CGFloat = 0.95) {
        guard Date().timeIntervalSince(lastUpdateTime) > 0.05 else { return }
        smoothVx *= factor
        smoothVy *= factor
    }

    // MARK: - 沙坑粘滞 (Stickiness Sandpit)

    /// 沙坑粘滞：光标在 UI 元素上时减速（保留方向），而非被拉向中心
    /// 类比：沙坑里走路 — 方向不变但速度变慢，用力跑就能冲出去
    /// - Parameter screenSize: 当前屏幕尺寸，用于坐标翻转
    private func applyStickiness(screenSize: CGSize) {
        guard ConfigManager.shared.currentConfig.assistEnabled,
              let scanner = uiScanner else { return }

        let config = ConfigManager.shared.currentConfig
        let R = CGFloat(config.assistRInfluence)
        let R_release = R * CGFloat(config.assistHysteresisRatio)
        let now = ProcessInfo.processInfo.systemUptime

        let near = scanner.nearElement
        let nearCenter = near.map { flippedCenter(of: $0, screenSize: screenSize) }
        let nearDist = nearCenter.map { distance(from: $0) } ?? .greatestFiniteMagnitude

        switch stickinessState {
        case .free:
            guard let near = near, let center = nearCenter, nearDist < R else { return }
            stickinessState = .tracking(near)
            trackedElementCenter = center
            lastElementSwitchTime = now
            scanner.lockElement(near)  // 锁住目标，防 jitter 跳变
            EventLogger.log(event: "STATE", frame: nil,
                            input: "free→tracking", output: "role=\(near.role) title=\(near.title) dist=\(Int(nearDist)) locked=true", duration: nil)
            applyStickyDelta(to: center, dist: nearDist, screenSize: screenSize)

        case .tracking(let element):
            let trackedDist = distance(from: trackedElementCenter)

            // 释放：距被跟踪元素太远（即使 nearElement 已 nil，也保持粘滞）
            if trackedDist > R_release {
                stickinessState = .free
                scanner.unlockElement()
                EventLogger.log(event: "STATE", frame: nil,
                                input: "tracking→free", output: "role=\(element.role) title=\(element.title) dist=\(Int(trackedDist)) locked=false", duration: nil)
                return
            }

            // 滞回切换：新元素要比当前元素近 40% 才切换
            if let near = near, near.id != element.id,
               now - lastElementSwitchTime > elementSwitchCooldown,
               let newCenter = nearCenter {
                let newDist = distance(from: newCenter)
                if newDist < trackedDist * 0.6 && newDist < R {
                    EventLogger.log(event: "STATE", frame: nil,
                                    input: "tracking→switch", output: "from=\(element.title) to=\(near.title) dist=\(Int(newDist))", duration: nil)
                    stickinessState = .tracking(near)
                    trackedElementCenter = newCenter
                    lastElementSwitchTime = now
                    scanner.lockElement(near)  // 切换目标，重新锁定
                }
            }

            applyStickyDelta(to: trackedElementCenter, dist: trackedDist, screenSize: screenSize)
        }
    }

    /// 粘滞日志节流计数器
    private var stickyLogCounter: Int = 0

    /// 缩放 targetPosition 的移动量（保留方向），实现沙坑减速效果
    private func applyStickyDelta(to center: CGPoint, dist: CGFloat, screenSize: CGSize) {
        let config = ConfigManager.shared.currentConfig
        let R = CGFloat(config.assistRInfluence)
        guard dist < R, dist > 0.001 else { return }

        // 粘滞曲线：中心最慢（minSpeed），边缘正常
        let t = dist / R
        let minSpeed = CGFloat(config.assistStickinessMinSpeed)
        var speedFactor = minSpeed + (1.0 - minSpeed) * t

        // 冲破机制：手速快 → 减弱粘滞 → 可自由穿过按钮
        let handSpeed = sqrt(smoothVx * smoothVx + smoothVy * smoothVy)
        let breakoutThreshold = CGFloat(config.assistBreakoutThreshold)
        let breakoutMaxSpeed = CGFloat(config.assistBreakoutMaxSpeed)
        var isBreakout = false
        if handSpeed > breakoutThreshold {
            let blend = min(1.0, (handSpeed - breakoutThreshold)
                            / (breakoutMaxSpeed - breakoutThreshold))
            speedFactor = speedFactor + (1.0 - speedFactor) * blend
            isBreakout = true
        }
        // 手速完全冲破 → 解锁目标，允许自由切换
        if handSpeed > breakoutMaxSpeed {
            uiScanner?.unlockElement()
            EventLogger.log(event: "LOCK", frame: nil, input: "breakout", output: "speed=\(Int(handSpeed))", duration: nil)
        }

        // 缩放移动量：保留方向，只改变速度
        let dx = targetPosition.x - currentPosition.x
        let dy = targetPosition.y - currentPosition.y
        targetPosition.x = currentPosition.x + dx * speedFactor
        targetPosition.y = currentPosition.y + dy * speedFactor

        // 节流日志：每 30 帧打一次
        stickyLogCounter += 1
        if stickyLogCounter % 30 == 0 {
            EventLogger.log(event: "STICKY", frame: nil,
                            input: "dist=\(Int(dist)) t=\(String(format:"%.2f",t)) handSpeed=\(Int(handSpeed))",
                            output: "factor=\(String(format:"%.3f",speedFactor)) breakout=\(isBreakout) delta=(\(Int(dx)),\(Int(dy)))",
                            duration: nil)
        }

        // 边界约束
        targetPosition.x = max(0, min(targetPosition.x, screenSize.width))
        targetPosition.y = max(0, min(targetPosition.y, screenSize.height))
    }

    /// AX 坐标系 → 屏幕坐标系（Y 轴翻转）
    private func flippedCenter(of el: UIElementInfo, screenSize: CGSize) -> CGPoint {
        CGPoint(x: el.frame.midX, y: screenSize.height - el.frame.midY)
    }

    /// 光标到指定点的欧几里得距离
    private func distance(from center: CGPoint) -> CGFloat {
        let dx = center.x - currentPosition.x
        let dy = center.y - currentPosition.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - 光标计算

    /// 计算最终光标位置（沙坑粘滞已前移到 applyStickiness 修改 targetPosition）
    func computeCursor(screenSize: CGSize, sensitivity: Float, dt: Double = 1.0 / 30.0, frameId: Int? = nil) -> CGPoint {
        var cursor = currentPosition
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            EventLogger.log(event: "computeCursor", frame: frameId,
                            input: "screenSize=(\(Int(screenSize.width)),\(Int(screenSize.height)))",
                            output: "cursor=(\(Int(cursor.x)),\(Int(cursor.y)))",
                            duration: duration)
        }

        // 注视偏移已禁用（用户要求纯手指控制，保留面部检测和 overlay）

        // 限制在屏幕内
        cursor.x = max(0, min(cursor.x, screenSize.width))
        cursor.y = max(0, min(cursor.y, screenSize.height))

        return cursor
    }
}
