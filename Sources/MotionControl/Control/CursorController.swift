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

    // MARK: - 校准状态

    enum CalibrationState {
        case idle           // 无手
        case calibrating    // 手刚出现，累积原点
        case tracking       // 正常跟踪
    }

    private(set) var calibrationState: CalibrationState = .idle

    /// 静止原点（归一化坐标，0~1），手在此位置时光标在屏幕中心
    var origin: CGPoint = CGPoint(x: 0.5, y: 0.4)

    /// 原点校准参数
    private var calibrationDuration: TimeInterval = 0.5  // 校准时长（左手延长）
    private var calibrationStartTime: Date = .distantPast
    private var originAccumulator: [CGPoint] = []
    private let maxOriginSamples = 15

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

    /// UI 元素扫描器（用于磁性吸引）
    var uiScanner: UIElementScanner? = nil
    
    /// 磁吸状态
    enum MagnetState {
        case idle
        case snap(UIElementInfo)
    }
    private var magnetState: MagnetState = .idle

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
    private var filterX = OneEuroFilter(fcMin: 0.8, beta: 0.05, fcD: 1.0)
    private var filterY = OneEuroFilter(fcMin: 0.8, beta: 0.05, fcD: 1.0)
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

    /// 手进入画面时开始校准原点
    func startCalibration(handedness: HandSide = .unknown) {
        filterX.reset()
        filterY.reset()
        filterTimeBase = 0
        calibrationState = .calibrating
        calibrationStartTime = Date()
        originAccumulator = []
        // 左手需要更长校准时间（位置方差大，原点更不稳定）
        calibrationDuration = (handedness == .left) ? 0.8 : 0.5
        // 重置帧丢失保护状态
        prevUpdateTime = 0
        prevTarget = .zero
        screenVelocityX = 0
        screenVelocityY = 0
        gapRecoveryUntil = 0
    }

    /// 手离开画面时重置
    func endCalibration() {
        calibrationState = .idle
        originAccumulator = []
        filterX.reset()
        filterY.reset()
        filterTimeBase = 0
        fingerActive = false
        // 重置帧丢失保护状态，避免手再出现时旧速度/预测残留
        prevUpdateTime = 0
        prevTarget = .zero
        screenVelocityX = 0
        screenVelocityY = 0
        gapRecoveryUntil = 0
    }

    /// 累积原点样本，校准完成后返回 true
    func accumulateOrigin(_ handCenter: CGPoint) -> Bool {
        guard calibrationState == .calibrating else { return true }

        originAccumulator.append(handCenter)
        let elapsed = Date().timeIntervalSince(calibrationStartTime)

        if elapsed >= calibrationDuration && originAccumulator.count >= 5 {
            // 校准完成：用 EMA 平均原点
            let avgX = originAccumulator.reduce(0) { $0 + $1.x } / CGFloat(originAccumulator.count)
            let avgY = originAccumulator.reduce(0) { $0 + $1.y } / CGFloat(originAccumulator.count)
            origin = CGPoint(x: avgX, y: avgY)
            calibrationState = .tracking
            fingerActive = true

            // 初始化 currentPosition 到屏幕中心，避免首帧跳 (0,0)
            if currentPosition == .zero {
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                currentPosition = CGPoint(x: screen.width / 2, y: screen.height / 2)
            }
            return true
        }
        return false
    }

    /// 绝对位置映射：手位置 → 光标位置（1€ Filter 平滑）
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
        let fx = filterX.filter(handCenter.x, time: t)
        let fy = filterY.filter(handCenter.y, time: t)

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
        let cursorX = screenCX - offsetX * screenSize.width * effectiveGain
        let cursorY = screenCY + offsetY * screenSize.height * effectiveGain

        // 设定目标位置，120Hz 定时器 Lerp 追赶
        let rawTarget = CGPoint(
            x: max(0, min(cursorX, screenSize.width)),
            y: max(0, min(cursorY, screenSize.height))
        )

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

    /// 重置光标状态（仅重置手指激活，磁吸状态复位）
    func resetCursor() {
        fingerActive = false
        magnetState = .idle
    }

    /// 衰减速度（补帧定时器每帧调用）
    /// 仅在 updateWithDelta 超过 50ms 未调用时才衰减，避免和 EMA 更新打架
    func decayVelocity(by factor: CGFloat = 0.95) {
        guard Date().timeIntervalSince(lastUpdateTime) > 0.05 else { return }
        smoothVx *= factor
        smoothVy *= factor
    }

    // MARK: - 光标计算

    /// 计算最终光标位置（加入磁吸 + 屏幕限制）
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

        // 磁吸：分辨率自适应阈值（基于屏幕对角线百分比）
        let diagonal = sqrt(screenSize.width * screenSize.width + screenSize.height * screenSize.height)
        let lockRadius = diagonal * 0.020   // 2% 对角线 ≈ 35px @ 1470×956
        let releaseRadius = diagonal * 0.030 // 3% ≈ 50px @ 1470×956

        if let scanner = uiScanner, !scanner.elements.isEmpty {
            switch magnetState {
            case .idle:
                // 全量扫描所有元素，找距离最近的
                var bestElement: UIElementInfo?
                var bestCenter = CGPoint.zero
                var bestDist: CGFloat = lockRadius

                for el in scanner.elements {
                    // AX frame 是屏幕坐标(y=0=顶)，转为底左坐标
                    let elCenter = CGPoint(
                        x: el.frame.midX,
                        y: screenSize.height - el.frame.midY
                    )
                    let dx = elCenter.x - cursor.x
                    let dy = elCenter.y - cursor.y
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < bestDist {
                        bestDist = dist
                        bestElement = el
                        bestCenter = elCenter
                    }
                }

                if let el = bestElement {
                    magnetState = .snap(el)
                    cursor = bestCenter
                }

            case .snap(let element):
                let elCenter = CGPoint(
                    x: element.frame.midX,
                    y: screenSize.height - element.frame.midY
                )
                let dx = elCenter.x - cursor.x
                let dy = elCenter.y - cursor.y
                let dist = sqrt(dx * dx + dy * dy)

                if dist > releaseRadius {
                    magnetState = .idle
                } else {
                    // 80% 拉向中心，20% 跟手
                    cursor.x += (elCenter.x - cursor.x) * 0.8
                    cursor.y += (elCenter.y - cursor.y) * 0.8
                }
            }
        }

        // 注视偏移已禁用（用户要求纯手指控制，保留面部检测和 overlay）
        // 如需重新启用，取消下方注释
        // if gazeActive {
        //     if cursor.x > 5 && cursor.x < screenSize.width - 5 {
        //         cursor.x += CGFloat(yawOffset) * screenSize.width * 0.05
        //     }
        //     if cursor.y > 5 && cursor.y < screenSize.height - 5 {
        //         cursor.y += CGFloat(pitchOffset) * screenSize.height * 0.05
        //     }
        // }

        // 限制在屏幕内
        cursor.x = max(0, min(cursor.x, screenSize.width))
        cursor.y = max(0, min(cursor.y, screenSize.height))

        return cursor
    }
}
