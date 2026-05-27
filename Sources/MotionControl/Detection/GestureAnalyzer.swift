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

    // 记录上次捏合事件的时间（原有）
    private var lastPinchTime: Date?

    /// 分析手部姿态结果，返回当前帧检测到的主要手势事件（只返回置信度最高的一个）。
    /// - Parameter hand: 手部关键点数据
    /// - Returns: 手势事件（若无手势则 type 为 .none，confidience 为 0）
    func analyze(_ hand: HandPoseResult) -> GestureEvent {
        let config = ConfigManager.shared.currentConfig

        // 从配置读取动态阈值（单位统一）
        let pinchThreshold = CGFloat(config.pinchThreshold)
        let gestureCooldown = TimeInterval(config.gestureCooldown) / 1000.0
        let doublePinchWindow = TimeInterval(config.doubleTapWindow) / 1000.0
        let openPalmThreshold = CGFloat(config.openPalmThreshold)
        let fistThreshold = CGFloat(config.fistThreshold)
        let thumbsUpMinDist = CGFloat(config.thumbsUpMinDist)
        let pointRatio = CGFloat(config.pointRatio)

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

        // --- pinch (捏合) ---
        if let thumb = hand.thumbTip, let index = hand.indexTip {
            let dist = hypot(thumb.x - index.x, thumb.y - index.y)
            if dist < pinchThreshold {
                let confidence = max(0.0, 1.0 - Double(dist / pinchThreshold))
                // 检查双击捏合
                var isDouble = false
                if let lastPinch = lastPinchTime,
                   now.timeIntervalSince(lastPinch) < doublePinchWindow {
                    isDouble = true
                }
                lastPinchTime = now

                let gestureType: GestureType = isDouble ? .doublePinch : .pinch
                consider(GestureEvent(gestureType: gestureType,
                                      confidence: confidence,
                                      timestamp: now,
                                      handPosition: handPos,
                                      velocity: velocity))
            }
        }

        // --- point (指点) ---
        if let indexTip = hand.indexTip,
           let middleTip = hand.middleTip,
           let ringTip = hand.ringTip,
           let littleTip = hand.littleTip,
           let wrist = hand.wrist,
           let thumbTip = hand.thumbTip {
            let indexLen = hypot(indexTip.x - wrist.x, indexTip.y - wrist.y)
            let middleLen = hypot(middleTip.x - wrist.x, middleTip.y - wrist.y)
            let ringLen = hypot(ringTip.x - wrist.x, ringTip.y - wrist.y)
            let littleLen = hypot(littleTip.x - wrist.x, littleTip.y - wrist.y)
            let avgOther = (middleLen + ringLen + littleLen) / 3.0
            if indexLen > avgOther * pointRatio && indexLen > openPalmThreshold {
                let confidence = min(1.0, Double(indexLen / (openPalmThreshold * 2)))
                consider(GestureEvent(gestureType: .point,
                                      confidence: confidence,
                                      timestamp: now,
                                      handPosition: handPos,
                                      velocity: velocity))
            }
        }

        // --- openPalm (手掌张开) ---
        if let thumb = hand.thumbTip,
           let index = hand.indexTip,
           let middle = hand.middleTip,
           let ring = hand.ringTip,
           let little = hand.littleTip,
           let wrist = hand.wrist {
            let thumbDist = hypot(thumb.x - wrist.x, thumb.y - wrist.y)
            let indexDist = hypot(index.x - wrist.x, index.y - wrist.y)
            let middleDist = hypot(middle.x - wrist.x, middle.y - wrist.y)
            let ringDist = hypot(ring.x - wrist.x, ring.y - wrist.y)
            let littleDist = hypot(little.x - wrist.x, little.y - wrist.y)
            let minDist = min(thumbDist, indexDist, middleDist, ringDist, littleDist)
            if minDist > openPalmThreshold {
                let avgDist = (thumbDist + indexDist + middleDist + ringDist + littleDist) / 5.0
                let confidence = min(1.0, Double(avgDist / (openPalmThreshold * 3)))
                consider(GestureEvent(gestureType: .openPalm,
                                      confidence: confidence,
                                      timestamp: now,
                                      handPosition: handPos,
                                      velocity: velocity))
            }
        }

        // --- fist (拳头) ---
        if let thumb = hand.thumbTip,
           let index = hand.indexTip,
           let middle = hand.middleTip,
           let ring = hand.ringTip,
           let little = hand.littleTip,
           let wrist = hand.wrist {
            let thumbDist = hypot(thumb.x - wrist.x, thumb.y - wrist.y)
            let indexDist = hypot(index.x - wrist.x, index.y - wrist.y)
            let middleDist = hypot(middle.x - wrist.x, middle.y - wrist.y)
            let ringDist = hypot(ring.x - wrist.x, ring.y - wrist.y)
            let littleDist = hypot(little.x - wrist.x, little.y - wrist.y)
            let maxDist = max(thumbDist, indexDist, middleDist, ringDist, littleDist)
            if maxDist < fistThreshold {
                let avgDist = (thumbDist + indexDist + middleDist + ringDist + littleDist) / 5.0
                let confidence = max(0.0, 1.0 - Double(avgDist / fistThreshold))
                consider(GestureEvent(gestureType: .fist,
                                      confidence: confidence,
                                      timestamp: now,
                                      handPosition: handPos,
                                      velocity: velocity))
            }
        }

        // --- thumbsUp (点赞) ---
        if let thumb = hand.thumbTip,
           let index = hand.indexTip,
           let middle = hand.middleTip,
           let ring = hand.ringTip,
           let little = hand.littleTip,
           let wrist = hand.wrist {
            let thumbDist = hypot(thumb.x - wrist.x, thumb.y - wrist.y)
            let indexDist = hypot(index.x - wrist.x, index.y - wrist.y)
            let middleDist = hypot(middle.x - wrist.x, middle.y - wrist.y)
            let ringDist = hypot(ring.x - wrist.x, ring.y - wrist.y)
            let littleDist = hypot(little.x - wrist.x, little.y - wrist.y)
            let otherMax = max(indexDist, middleDist, ringDist, littleDist)
            if thumbDist > thumbsUpMinDist && otherMax < fistThreshold {
                let confidence = min(1.0, Double(thumbDist / (thumbsUpMinDist * 3)))
                consider(GestureEvent(gestureType: .thumbsUp,
                                      confidence: confidence,
                                      timestamp: now,
                                      handPosition: handPos,
                                      velocity: velocity))
            }
        }

        // --- grab (抓取) 等，保留原有占位
        // --- peace (剪刀) 等预留，需要额外关键点

        // =====================================================
        // 新增：时间序列检测（滑动窗口，tap, doubleTap, dualTap, dualRelease, swipe）
        // =====================================================
        // 更新滑动窗口
        let indexY = hand.indexTip?.y
        let middleY = hand.middleTip?.y
        let wristY  = hand.wrist?.y

        // 只有当三个关键点都存在时才进行时间序列检测
        if let iY = indexY, let mY = middleY, let wY = wristY {
            yHistory.append((indexY: iY, middleY: mY, wristY: wY, timestamp: now))
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
            // 关键点丢失时清空历史，重置状态
            yHistory.removeAll()
            resetSequenceStates()
        }

        // --- 计算用于日志的拇指–食指距离（若没有可用关键点则用0）
        let thumbIndexDist: CGFloat = {
            guard let t = hand.thumbTip, let i = hand.indexTip else { return 0 }
            return hypot(t.x - i.x, t.y - i.y)
        }()

        // --- 冷却与去重 ---
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
            // 记录日志
            let inputStr = "gesture_analyze type=\(event.gestureType) dist=\(String(format: "%.1f", thumbIndexDist))"
            let outputStr = "gesture=\(finalEvent.gestureType) confidence=\(String(format: "%.2f", finalEvent.confidence)) isRepeat=\(finalEvent.isRepeat)"
            EventLogger.log(event: "gesture_analyze", frame: nil, input: inputStr, output: outputStr, duration: nil)

            lastEventType = event.gestureType
            lastEventTime = now
            return finalEvent
        }

        // 无手势
        let noneEvent = GestureEvent(gestureType: .none, confidence: 0, timestamp: now, handPosition: handPos, velocity: velocity)
        let inputStr = "gesture_analyze type=none dist=\(String(format: "%.1f", thumbIndexDist))"
        let outputStr = "gesture=none confidence=0.00 isRepeat=false"
        EventLogger.log(event: "gesture_analyze", frame: nil, input: inputStr, output: outputStr, duration: nil)

        lastEventType = .none
        lastEventTime = now
        return noneEvent
    }

    // MARK: - 时间序列检测
    private func detectSequence(currentTime: Date) -> GestureEvent? {
        // 常数阈值（后续可按配置改为动态）
        let tapDropThreshold: CGFloat = 15.0
        let tapRiseThreshold: CGFloat = 10.0
        let dualDropThreshold: CGFloat = 12.0
        let dualRiseThreshold: CGFloat = 8.0
        let swipeThreshold: CGFloat = 30.0
        let tapDropMaxDuration: TimeInterval = 0.2
        let tapRiseMaxDuration: TimeInterval = 0.2
        let doubleTapInterval: TimeInterval = 0.4

        guard let last = yHistory.last,
              let prev = yHistory.dropLast().last else { return nil }

        let indexDelta = last.indexY - prev.indexY
        let middleDelta = last.middleY - prev.middleY
        let wristDelta = last.wristY - prev.wristY

        // 1. Swipe 检测 (基于手腕Y的累积位移)
        if abs(wristDelta) > 2.0 {
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
            swipeAccumulatedY *= 0.8
            if swipeAccumulatedY < 2.0 {
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
            if delta > riseThreshold {
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
        yHistory.removeAll()
        indexTapPhase = .idle
        dualTapPhase = .idle
        pendingDualTap = nil
        swipeAccumulatedY = 0
        swipeDirection = nil
        lastSingleTapTime = nil
    }
}
