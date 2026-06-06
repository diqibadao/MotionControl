import Foundation
import CoreGraphics

/// 手势事件，包含类型、置信度、时间戳、手部位置、是否重复和移动速度。
struct GestureEvent {
    let gestureType: GestureType
    let confidence: Double
    let timestamp: Date
    let handPosition: CGPoint
    let isRepeat: Bool
    let velocity: CGPoint

    init(gestureType: GestureType,
                confidence: Double,
                timestamp: Date = Date(),
                handPosition: CGPoint = .zero,
                isRepeat: Bool = false,
                velocity: CGPoint = .zero) {
        self.gestureType = gestureType
        self.confidence = confidence
        self.timestamp = timestamp
        self.handPosition = handPosition
        self.isRepeat = isRepeat
        self.velocity = velocity
    }
}

/// 手势分析引擎，利用 HandPoseResult 的关键点判断手势。
class GestureAnalyzer {

    // MARK: - 滑动窗口
    private var yHistory: [(indexY: CGFloat, middleY: CGFloat, wristY: CGFloat, timestamp: Date)] = []
    private let maxHistoryCount = 10

    // MARK: - 关键点丢失容错
    private var consecutiveLostFrames = 0
    private let maxLostFrames = 5  // 连续丢失 5 帧后才重置状态（~166ms @ 30fps）

    // MARK: - Tap 状态机
    private enum TapPhase { case idle, dropping, rising, complete }
    private var indexTapPhase: TapPhase = .idle
    private var indexTapDropStartY: CGFloat = 0
    private var indexTapDropStartTime: Date = Date()
    private var lastSingleTapTime: Date? = nil

    // MARK: - DualTap 状态机
    private enum DualTapPhase { case idle, dropping, complete }
    private var dualTapPhase: DualTapPhase = .idle
    private var pendingDualTap: GestureType? = nil   // .dualTap 或 .dualRelease
    private var dualTapDropStartTime: Date = Date()

    // MARK: - Swipe 累计器
    private var swipeAccumulatedY: CGFloat = 0
    private var swipeDirection: GestureType? = nil   // .swipeUp 或 .swipeDown

    // MARK: - 记录上次事件类型和时间，用于去重
    private var lastEventType: GestureType = .none
    private var lastEventTime: Date = .distantPast

    init() {}

    /// 分析手部姿态结果，返回当前帧检测到的主要手势事件（只返回置信度最高的一个）。
    /// - Parameter hand: 手部关键点数据
    /// - Returns: 手势事件（若无手势则 type 为 .none，confidience 为 0）
    func analyze(_ hand: HandPoseResult) -> GestureEvent {
        let config = ConfigManager.shared.currentConfig

        // 只保留去重冷却需要的参数
        let gestureCooldown = TimeInterval(config.gestureCooldown) / 1000.0

        var bestEvent: GestureEvent? = nil

        // 辅助函数：比较并保存置信度最高的事件
        func consider(_ event: GestureEvent) {
            if let current = bestEvent {
                if event.confidence > current.confidence {
                    bestEvent = event
                }
            } else {
                bestEvent = event
            }
        }

        let now = Date()
        // 获取手部位置（以手腕为例）
        let handPos = hand.wrist ?? .zero
        // 计算手部速度（需要前后帧对比，此处简化为零）
        let velocity = CGPoint.zero

        // ---- 时间序列检测（滑动窗口，tap, doubleTap, dualTap, dualRelease, swipe） ----
        if let indexY = hand.indexTip?.y,
           let middleY = hand.middleTip?.y,
           let wristY = hand.wrist?.y {
            consecutiveLostFrames = 0
            yHistory.append((indexY: indexY, middleY: middleY, wristY: wristY, timestamp: now))
            if yHistory.count > maxHistoryCount {
                yHistory.removeFirst()
            }

            // 只有历史帧数 >= 2 时才能做差分检测
            if yHistory.count >= 2 {
                let seqEvent = detectSequence(currentTime: now)
                if let seq = seqEvent {
                    consider(seq)
                }
            }
        } else {
            // 关键点短暂丢失不立即重置，连续丢失超过 maxLostFrames 才清空
            consecutiveLostFrames += 1
            if consecutiveLostFrames > maxLostFrames {
                yHistory.removeAll()
                resetSequenceStates()
            }
        }

        // ---- 冷却与去重 ----
        if let event = bestEvent {
            // 如果冷却时间内出现相同事件且在 cooldownInterval 内，标记为重复
            let isRepeat: Bool
            if event.gestureType == lastEventType && now.timeIntervalSince(lastEventTime) < gestureCooldown {
                isRepeat = true
            } else {
                isRepeat = false
            }
            let finalEvent = GestureEvent(gestureType: event.gestureType,
                                          confidence: event.confidence,
                                          timestamp: now,
                                          handPosition: event.handPosition,
                                          isRepeat: isRepeat,
                                          velocity: event.velocity)
            // 记录日志（旧手势已移除，dist 固定为 0）
            let inputStr = "gesture_analyze type=\(event.gestureType) dist=0.0"
            let outputStr = "gesture=\(finalEvent.gestureType) confidence=\(String(format: "%.2f", finalEvent.confidence)) isRepeat=\(finalEvent.isRepeat)"
            EventLogger.log(event: "gesture_analyze", frame: nil, input: inputStr, output: outputStr, duration: nil)

            lastEventType = event.gestureType
            lastEventTime = now
            return finalEvent
        }

        // 无手势
        let noneEvent = GestureEvent(gestureType: .none, confidence: 0, timestamp: now, handPosition: handPos, velocity: velocity)
        let inputStr = "gesture_analyze type=none dist=0.0"
        let outputStr = "gesture=none confidence=0.00 isRepeat=false"
        EventLogger.log(event: "gesture_analyze", frame: nil, input: inputStr, output: outputStr, duration: nil)

        lastEventType = .none
        lastEventTime = now
        return noneEvent
    }

    // MARK: - 时间序列检测
    private func detectSequence(currentTime: Date) -> GestureEvent? {
        // 常数阈值（Vision 坐标归一化到 0~1）
        let tapDropThreshold: CGFloat = 0.0005
        let tapRiseThreshold: CGFloat = 0.0003
        let dualDropThreshold: CGFloat = 0.0005
        let dualRiseThreshold: CGFloat = 0.0003
        let swipeThreshold: CGFloat = 0.001
        let tapDropMaxDuration: TimeInterval = 0.2
        let tapRiseMaxDuration: TimeInterval = 0.2
        let doubleTapInterval: TimeInterval = 0.4

        guard let last = yHistory.last,
              let prev = yHistory.dropLast().last else { return nil }

        let indexDelta = last.indexY - prev.indexY
        let middleDelta = last.middleY - prev.middleY
        let wristDelta = last.wristY - prev.wristY

        // 1. Swipe 检测 (基于手腕Y的累积位移)
        if abs(wristDelta) > 0.002 {
            if wristDelta > 0 {  // 向下
                if swipeDirection == .swipeDown || swipeDirection == nil {
                    swipeAccumulatedY += wristDelta
                    swipeDirection = .swipeDown
                } else {
                    swipeAccumulatedY = wristDelta
                    swipeDirection = .swipeDown
                }
            } else if wristDelta < 0 { // 向上
                if swipeDirection == .swipeUp || swipeDirection == nil {
                    swipeAccumulatedY += abs(wristDelta)
                    swipeDirection = .swipeUp
                } else {
                    swipeAccumulatedY = abs(wristDelta)
                    swipeDirection = .swipeUp
                }
            }

            if swipeAccumulatedY > swipeThreshold, let dir = swipeDirection {
                swipeAccumulatedY = 0
                swipeDirection = nil
                let confidence: Double = 0.9
                let gestureType: GestureType = dir
                return GestureEvent(gestureType: gestureType,
                                    confidence: confidence,
                                    timestamp: currentTime,
                                    handPosition: (yHistory.last?.wristY).map { CGPoint(x: 0, y: $0) } ?? .zero,
                                    velocity: CGPoint.zero)
            }
        } else {
            // 手腕静止：衰减累积量，低于 swipe 阈值时复位
            swipeAccumulatedY *= 0.8
            if swipeAccumulatedY < swipeThreshold {
                swipeAccumulatedY = 0
                swipeDirection = nil
            }
        }

        // 2. 单手 Index Tap 检测 (状态机)
        handleIndexTap(currentTime: currentTime, delta: indexDelta, dropThreshold: tapDropThreshold,
                       riseThreshold: tapRiseThreshold, dropMaxDuration: tapDropMaxDuration,
                       riseMaxDuration: tapRiseMaxDuration)

        // 如果单指 Tap 完成
        if indexTapPhase == .complete {
            indexTapPhase = .idle
            // 检查双击
            if let lastTap = lastSingleTapTime,
               currentTime.timeIntervalSince(lastTap) < doubleTapInterval {
                // 两次 tap 在间隔内 → doubleTap
                lastSingleTapTime = nil
                return GestureEvent(gestureType: .indexDoubleTap,
                                    confidence: 0.9,
                                    timestamp: currentTime,
                                    handPosition: (yHistory.last?.indexY).map { CGPoint(x: 0, y: $0) } ?? .zero,
                                    velocity: CGPoint.zero)
            } else {
                lastSingleTapTime = currentTime
                return GestureEvent(gestureType: .indexTap,
                                    confidence: 0.85,
                                    timestamp: currentTime,
                                    handPosition: (yHistory.last?.indexY).map { CGPoint(x: 0, y: $0) } ?? .zero,
                                    velocity: CGPoint.zero)
            }
        }

        // 3. Dual Tap / Dual Release 检测 (状态机)
        handleDualTap(currentTime: currentTime, indexDelta: indexDelta, middleDelta: middleDelta,
                      dropThreshold: dualDropThreshold, riseThreshold: dualRiseThreshold,
                      dropMaxDuration: tapDropMaxDuration, riseMaxDuration: tapRiseMaxDuration)

        // 如果双指状态完成
        if dualTapPhase == .complete, let pending = pendingDualTap {
            dualTapPhase = .idle
            let gesture = pending
            pendingDualTap = nil
            return GestureEvent(gestureType: gesture,
                                confidence: 0.85,
                                timestamp: currentTime,
                                handPosition: (yHistory.last?.middleY).map { CGPoint(x: 0, y: $0) } ?? .zero,
                                velocity: CGPoint.zero)
        }

        return nil
    }

    // MARK: - 食指 Tap 状态机
    private func handleIndexTap(currentTime: Date, delta: CGFloat,
                                dropThreshold: CGFloat, riseThreshold: CGFloat,
                                dropMaxDuration: TimeInterval, riseMaxDuration: TimeInterval) {
        switch indexTapPhase {
        case .idle:
            if delta > dropThreshold {
                indexTapPhase = .dropping
                indexTapDropStartY = yHistory.last?.indexY ?? 0
                indexTapDropStartTime = currentTime
            }
        case .dropping:
            // 食指回升（delta 为负且绝对值超过 riseThreshold）
            if delta < -riseThreshold {
                indexTapPhase = .rising
            } else if currentTime.timeIntervalSince(indexTapDropStartTime) > dropMaxDuration {
                indexTapPhase = .idle
            }
        case .rising:
            let currentY = yHistory.last?.indexY ?? 0
            let dropAmount = currentY - indexTapDropStartY
            if dropAmount > dropThreshold * 0.5 && delta > 0 {
                indexTapPhase = .complete
            } else if currentTime.timeIntervalSince(indexTapDropStartTime) > (dropMaxDuration + riseMaxDuration) {
                indexTapPhase = .idle
            }
        case .complete:
            indexTapPhase = .idle
        }
    }

    // MARK: - 双指 Tap/DualRelease 状态机
    private func handleDualTap(currentTime: Date, indexDelta: CGFloat, middleDelta: CGFloat,
                               dropThreshold: CGFloat, riseThreshold: CGFloat,
                               dropMaxDuration: TimeInterval, riseMaxDuration: TimeInterval) {
        let bothDown = (indexDelta > dropThreshold) && (middleDelta > dropThreshold)
        let bothUp   = (indexDelta < -riseThreshold) && (middleDelta < -riseThreshold)

        switch dualTapPhase {
        case .idle:
            if bothDown {
                dualTapPhase = .dropping
                pendingDualTap = .dualTap
                dualTapDropStartTime = currentTime
            }
        case .dropping:
            if bothUp {
                // 完成一次下降后上升 → 先完成dualTap（已记录），然后标记dualRelease
                pendingDualTap = .dualRelease
                dualTapPhase = .complete
            } else if currentTime.timeIntervalSince(dualTapDropStartTime) > dropMaxDuration {
                dualTapPhase = .idle
                pendingDualTap = nil
            }
        case .complete:
            dualTapPhase = .idle
            pendingDualTap = nil
        }
    }

    // MARK: - 重置时间序列状态
    private func resetSequenceStates() {
        consecutiveLostFrames = 0
        yHistory.removeAll()
        indexTapPhase = .idle
        dualTapPhase = .idle
        pendingDualTap = nil
        swipeAccumulatedY = 0
        swipeDirection = nil
        lastSingleTapTime = nil
    }
}
