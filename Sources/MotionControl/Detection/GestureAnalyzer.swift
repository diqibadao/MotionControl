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

/// 手势分析引擎，用静态姿态识别手势（指尖相对于指关节的位置）
/// 行业标准：不看指尖"动了多少"，只看指尖在关节"上面还是下面"
class GestureAnalyzer {

    // MARK: - 点击/拖拽/滚轮（统一捏合手势）
    /// 当前是否捏合中（供外部读取，用于光标冻结）
    private(set) var isPinching = false
    private var pinchRecoveryUntil: Date = .distantPast  // 松手后冻结光标截止时间
    
    /// 光标是否应冻结（捏合中 + 松手后 200ms 冷却期）
    var cursorFrozen: Bool { isPinching || Date() < pinchRecoveryUntil }
    private var pinchStartTime: Date = .distantPast   // 捏合开始时间
    private var pinchStartPos: CGPoint = .zero        // 捏合开始位置
    private var pinchMoved = false                     // 捏合期间是否移动过
    private var lastClickTime: Date = .distantPast
    private var pinchReleasedBetweenClicks = true
    private let doubleClickWindow: TimeInterval = 0.3
    private let pinchThreshold: CGFloat = 0.06

    // MARK: - 滚轮（指尖中点 + 位移阈值）
    private var scrollOrigin: CGPoint? = nil
    private var scrollTick: CGFloat = 0.05
    private var lastScrollFire: Date = .distantPast
    private let scrollMinInterval: TimeInterval = 0.05

    // MARK: - 关键点丢失容错
    private var consecutiveLostFrames = 0
    private let maxLostFrames = 5

    // MARK: - 记录上次事件类型和时间，用于冷却去重
    private var lastEventType: GestureType = .none
    private var lastEventTime: Date = .distantPast

    init() {}

    /// 每帧分析手部姿态，返回手势事件
    func analyze(_ hand: HandPoseResult) -> GestureEvent {
        let config = ConfigManager.shared.currentConfig
        let gestureCooldown = TimeInterval(config.gestureCooldown) / 1000.0  // 默认200ms冷却

        var bestEvent: GestureEvent? = nil

        func consider(_ event: GestureEvent) {
            if let current = bestEvent {
                if event.confidence > current.confidence { bestEvent = event }
            } else {
                bestEvent = event
            }
        }

        let now = Date()
        let handPos = hand.wrist ?? .zero
        let velocity = CGPoint.zero

        // ---- 统一的捏合手势：单击/双击/拖拽/滚轮 ----
        if let thumbTip = hand.thumbTip, let indexTip = hand.indexTip {
            consecutiveLostFrames = 0

            let dx = thumbTip.x - indexTip.x
            let dy = thumbTip.y - indexTip.y
            let distance = sqrt(dx*dx + dy*dy)
            let pinchingNow = distance < pinchThreshold
            let palmCenter = hand.palmCenter ?? handPos

            // 刚捏合：记录起点
            if pinchingNow && !isPinching {
                pinchStartTime = now
                pinchStartPos = palmCenter
                pinchMoved = false
            }

            // 捏合中 → 弹力摇杆：离原点越远滚越快，回原点 = 停，过原点 = 反向
            if pinchingNow && isPinching {
                let displacement = palmCenter.y - pinchStartPos.y
                if abs(displacement) > scrollTick {
                    pinchMoved = true
                    // 线性映射：maxDisplacement=0.3 → maxSpeed=10行
                    let maxDisp: CGFloat = 0.3
                    let maxSpeed: CGFloat = 10.0
                    let ratio = min(abs(displacement) / maxDisp, 1.0)
                    let curve = pow(ratio, 2.0)  // 平方曲线：微操放大，快速收拢
                    let speed = curve * maxSpeed
                    let rows = max(1.0, speed * scrollMinInterval)
                    consider(GestureEvent(gestureType: (displacement > 0 ? .scrollUp : .scrollDown),
                                          confidence: Double(rows) / 10.0,
                                          timestamp: now, handPosition: handPos, velocity: .zero))
                }
            }

            // 松手：捏了短时间 + 手没动 → 单击/双击
            if !pinchingNow && isPinching {
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
                pinchReleasedBetweenClicks = true
                pinchRecoveryUntil = Date().addingTimeInterval(0.2)  // 松手后 200ms 冷却
            }

            isPinching = pinchingNow
        } else {
            consecutiveLostFrames += 1
            if consecutiveLostFrames > maxLostFrames {
                isPinching = false
            }
        }

        // ---- 滚轮：指尖中点 + 位移阈值 ----
        let mode = hand.fingerMode
        if mode == .scroll, let indexTip = hand.indexTip, let middleTip = hand.middleTip {
            let tipY = (indexTip.y + middleTip.y) / 2
            if scrollOrigin == nil {
                scrollOrigin = CGPoint(x: 0, y: tipY)
            }
            if let origin = scrollOrigin, now.timeIntervalSince(lastScrollFire) >= scrollMinInterval {
                let dy = tipY - origin.y
                if dy > scrollTick {
                    let rows = max(1, Int(dy / scrollTick))
                    consider(GestureEvent(gestureType: .scrollUp,
                                          confidence: min(Double(rows) / 5.0, 1.0),
                                          timestamp: now, handPosition: handPos, velocity: .zero))
                    scrollOrigin = CGPoint(x: 0, y: tipY)
                    lastScrollFire = now
                } else if dy < -scrollTick {
                    let rows = max(1, Int(abs(dy) / scrollTick))
                    consider(GestureEvent(gestureType: .scrollDown,
                                          confidence: min(Double(rows) / 5.0, 1.0),
                                          timestamp: now, handPosition: handPos, velocity: .zero))
                    scrollOrigin = CGPoint(x: 0, y: tipY)
                    lastScrollFire = now
                }
            }
        } else {
            scrollOrigin = nil
        }

        // ---- 冷却与去重（滚动/切桌面事件免除冷却以支持连续触发） ----
        if let event = bestEvent {
            let isContinuous = event.gestureType == .scrollUp || event.gestureType == .scrollDown
                            || event.gestureType == .swipeLeft || event.gestureType == .swipeRight
            let isRepeat = !isContinuous &&
                           event.gestureType == lastEventType &&
                           now.timeIntervalSince(lastEventTime) < gestureCooldown
            let finalEvent = GestureEvent(gestureType: event.gestureType,
                                          confidence: event.confidence,
                                          timestamp: now,
                                          handPosition: event.handPosition,
                                          isRepeat: isRepeat,
                                          velocity: event.velocity)
            let inputStr = "gesture_analyze type=\(event.gestureType) dist=0.0"
            let outputStr = "gesture=\(finalEvent.gestureType) confidence=\(String(format: "%.2f", finalEvent.confidence)) isRepeat=\(finalEvent.isRepeat)"
            EventLogger.log(event: "gesture_analyze", frame: nil, input: inputStr, output: outputStr, duration: nil)

            lastEventType = event.gestureType
            lastEventTime = now
            return finalEvent
        }

        // 无手势
        let noneEvent = GestureEvent(gestureType: .none, confidence: 0, timestamp: now,
                                     handPosition: handPos, velocity: velocity)
        EventLogger.log(event: "gesture_analyze", frame: nil,
                        input: "gesture_analyze type=none dist=0.0",
                        output: "gesture=none confidence=0.00 isRepeat=false", duration: nil)

        lastEventType = .none
        lastEventTime = now
        return noneEvent
    }
}
