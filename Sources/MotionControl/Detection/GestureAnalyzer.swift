import Foundation
import CoreGraphics

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

/// 手势分析引擎：自适应归一化 + 时序状态机
class GestureAnalyzer {

    // MARK: - 点击/拖拽/滚轮
    private(set) var isPinching = false
    private var pinchRecoveryUntil: Date = .distantPast
    /// 光标是否应冻结（捏合中 + 松手后 200ms 冷却期，但拖拽中不解冻）
    var cursorFrozen: Bool { (isPinching && !dragStarted) || Date() < pinchRecoveryUntil }
    private var pinchStartTime: Date = .distantPast
    private var pinchStartPos: CGPoint = .zero
    private var pinchMoved = false
    private var dragStarted = false
    private var dragMinHoldUntil: Date = .distantPast  // 拖拽最小保持时间    // 拖拽是否已开始（防重复发送）
    private var lastClickTime: Date = .distantPast
    private var pinchReleasedBetweenClicks = true
    private let doubleClickWindow: TimeInterval = 0.3
    private let pinchRatioThreshold: CGFloat = 0.18
    private var scrollTick: CGFloat = 0.05

    // MARK: - 关键点丢失容错
    private var consecutiveLostFrames = 0
    private let maxLostFrames = 5

    // MARK: - 时序状态机
    private var pinchConfirmFrames = 0
    private var releaseConfirmFrames = 0
    private let confirmThreshold = 3

    // MARK: - 冷却
    private var lastEventType: GestureType = .none
    private var lastEventTime: Date = .distantPast
    private var frameCount = 0  // 诊断用帧计数

    init() {}

    func analyze(_ hand: HandPoseResult) -> GestureEvent {
        let config = ConfigManager.shared.currentConfig
        let gestureCooldown = TimeInterval(config.gestureCooldown) / 1000.0

        var bestEvent: GestureEvent? = nil

        func consider(_ event: GestureEvent) {
            if let current = bestEvent {
                if event.confidence > current.confidence { bestEvent = event }
            } else { bestEvent = event }
        }

        let now = Date()
        frameCount += 1
        let handPos = hand.wrist ?? .zero
        let velocity = CGPoint.zero

        // ---- 自适应归一化捏合检测 ----
        if let thumbTip = hand.thumbTip, let indexTip = hand.indexTip,
           let wrist = hand.wrist, let middleTip = hand.middleTip {

            consecutiveLostFrames = 0
            let fingerDist = hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y)
            let handSpan = hypot(wrist.x - (hand.indexMCP?.x ?? middleTip.x), wrist.y - (hand.indexMCP?.y ?? middleTip.y))
            let pinchRatio = handSpan > 0.001 ? fingerDist / handSpan : 999

            let rawPinch = pinchRatio < pinchRatioThreshold
            let palmCenter = hand.palmCenter ?? handPos

            if rawPinch { pinchConfirmFrames += 1; releaseConfirmFrames = 0 }
            else { releaseConfirmFrames += 1; pinchConfirmFrames = 0 }

            let pinchingNow = pinchConfirmFrames >= confirmThreshold

            if pinchingNow && !isPinching {
                pinchStartTime = now
                pinchStartPos = palmCenter
                pinchMoved = false
                dragStarted = false
            }

            if pinchingNow && isPinching {
                let dx = palmCenter.x - pinchStartPos.x
                let dy = palmCenter.y - pinchStartPos.y
                let moved = hypot(dx, dy)
                if moved > scrollTick {
                    pinchMoved = true
                    if abs(dx) > abs(dy) * 0.5 {
                        // 水平移动为主 → 拖拽
                        if !dragStarted {
                            dragStarted = true
                            dragMinHoldUntil = Date().addingTimeInterval(0.3)
                            EventLogger.log(event:"drag_diag", frame:nil,
                                input:"dragStart frame=\(frameCount) pinchConfirm=\(pinchConfirmFrames) releaseConfirm=\(releaseConfirmFrames) pinchingNow=\(pinchingNow) isPinching=\(isPinching)",
                                output:"", duration:nil)  // 最小拖拽 300ms
                            consider(GestureEvent(gestureType: .dragStart, confidence: 0.9,
                                                  timestamp: now, handPosition: handPos, velocity: CGPoint(x: dx, y: dy)))
                        }
                    } else {
                        // 垂直为主 → 滚轮
                        let maxDisp: CGFloat = 0.3; let maxSpeed: CGFloat = 10.0
                        let curve = pow(min(abs(dy) / maxDisp, 1.0), 2.0)
                        let rows = max(1.0, curve * maxSpeed)
                        consider(GestureEvent(gestureType: (dy > 0 ? .scrollUp : .scrollDown),
                                              confidence: Double(rows) / 10.0,
                                              timestamp: now, handPosition: handPos, velocity: .zero))
                    }
                }
            }

            if releaseConfirmFrames >= confirmThreshold && isPinching {
                let holdDuration = now.timeIntervalSince(pinchStartTime)
                if !pinchMoved && holdDuration < 0.5 {
                    let dt = now.timeIntervalSince(lastClickTime)
                    if dt < doubleClickWindow && pinchReleasedBetweenClicks {
                        consider(GestureEvent(gestureType: .indexDoubleTap, confidence: 0.9,
                                              timestamp: now, handPosition: handPos, velocity: velocity))
                        lastClickTime = .distantPast
                    } else {
                        consider(GestureEvent(gestureType: .indexTap, confidence: 0.9,
                                              timestamp: now, handPosition: handPos, velocity: velocity))
                        lastClickTime = now
                    }
                    pinchReleasedBetweenClicks = false
                }
                if pinchMoved && Date() >= dragMinHoldUntil {
                    EventLogger.log(event:"drag_diag", frame:nil,
                        input:"dragEnd frame=\(frameCount) dragDuration=\(String(format:"%.0f", Date().timeIntervalSince(pinchStartTime)*1000))ms releaseConfirm=\(releaseConfirmFrames) minHold=\(dragMinHoldUntil.timeIntervalSinceNow < 0 ? "passed":"waiting")",
                        output:"", duration:nil)
                    consider(GestureEvent(gestureType: .dragEnd, confidence: 0.9,
                                          timestamp: now, handPosition: handPos, velocity: velocity))
                }
                pinchReleasedBetweenClicks = true
                pinchRecoveryUntil = Date().addingTimeInterval(0.2)
            }

            if releaseConfirmFrames >= confirmThreshold { isPinching = false }
            else if pinchingNow { isPinching = true }

        } else {
            consecutiveLostFrames += 1
            pinchConfirmFrames = 0
            releaseConfirmFrames += 1
            if consecutiveLostFrames > maxLostFrames { isPinching = false }
            if releaseConfirmFrames >= confirmThreshold { isPinching = false }
        }

        // ---- 冷却与去重 ----
        if let event = bestEvent {
            let isContinuous = event.gestureType == .scrollUp || event.gestureType == .scrollDown
            let isRepeat = !isContinuous && event.gestureType == lastEventType &&
                           now.timeIntervalSince(lastEventTime) < gestureCooldown
            let finalEvent = GestureEvent(gestureType: event.gestureType,
                                          confidence: event.confidence, timestamp: now,
                                          handPosition: event.handPosition,
                                          isRepeat: isRepeat, velocity: event.velocity)
            EventLogger.log(event: "gesture_analyze", frame: nil,
                            input: "gesture_analyze type=\(event.gestureType)",
                            output: "gesture=\(finalEvent.gestureType) confidence=\(String(format: "%.2f", finalEvent.confidence)) isRepeat=\(finalEvent.isRepeat)", duration: nil)
            lastEventType = event.gestureType
            lastEventTime = now
            return finalEvent
        }

        let noneEvent = GestureEvent(gestureType: .none, confidence: 0, timestamp: now,
                                     handPosition: handPos, velocity: velocity)
        EventLogger.log(event: "gesture_analyze", frame: nil,
                        input: "gesture_analyze type=none",
                        output: "gesture=none confidence=0.00 isRepeat=false", duration: nil)
        lastEventType = .none
        lastEventTime = now
        return noneEvent
    }
}