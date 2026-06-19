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

    // MARK: - 手指弯曲状态（用于边沿触发）
    // "指尖Y < PIP关节Y" = 手指弯曲（Vision 坐标系原点左下，指尖弯下来后 Y 变小）
    private var indexBent = false     // 食指是否弯曲中
    private var middleBent = false    // 中指是否弯曲中

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

        // ---- 静态姿态检测：每帧独立判断手指弯曲状态 ----
        // 食指弯曲 = 指尖低于 PIP 关节（Vision 归一化坐标，原点左下）
        if let indexTipY = hand.indexTip?.y, let indexPIPY = hand.indexPIP?.y,
           let middleTipY = hand.middleTip?.y, let middlePIPY = hand.middlePIP?.y {
            consecutiveLostFrames = 0

            let indexIsBent = indexTipY < indexPIPY      // 食指指尖低于指关节 = 弯曲
            let middleIsBent = middleTipY < middlePIPY   // 中指指尖低于指关节 = 弯曲

            // 边沿触发：从未弯→弯的瞬间发射手势事件
            if indexIsBent && !indexBent {
                consider(GestureEvent(gestureType: .indexTap, confidence: 0.9,
                                      timestamp: now, handPosition: handPos, velocity: velocity))
            }
            if middleIsBent && !middleBent {
                consider(GestureEvent(gestureType: .pinch, confidence: 0.85,
                                      timestamp: now, handPosition: handPos, velocity: velocity))
            }
            // 食指+中指同时从未弯→弯 = 双击（按优先级选食指单击或双击）
            if indexIsBent && middleIsBent && (!indexBent || !middleBent) {
                consider(GestureEvent(gestureType: .indexDoubleTap, confidence: 0.8,
                                      timestamp: now, handPosition: handPos, velocity: velocity))
            }

            indexBent = indexIsBent
            middleBent = middleIsBent
        } else {
            consecutiveLostFrames += 1
            if consecutiveLostFrames > maxLostFrames {
                indexBent = false
                middleBent = false
            }
        }

        // ---- 冷却与去重 ----
        if let event = bestEvent {
            let isRepeat = event.gestureType == lastEventType &&
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
