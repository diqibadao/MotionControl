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

    // MARK: - 距离阈值 (像素坐标)
    private let pinchThreshold: CGFloat = 40
    private let openPalmThreshold: CGFloat = 100
    private let fistThreshold: CGFloat = 50
    private let thumbsUpMinDist: CGFloat = 80
    private let pointRatio: CGFloat = 1.5
    // 冷却时间（秒），避免同一手势短时间内重复触发
    private let cooldownInterval: TimeInterval = 0.3
    // 双击捏合时间窗口
    private let doublePinchWindow: TimeInterval = 0.5

    // 记录上次捏合事件的时间
    private var lastPinchTime: Date?
    // 记录上次事件类型和时间，用于去重
    private var lastEventType: GestureType = .none
    private var lastEventTime: Date = .distantPast

    init() {}

    /// 分析手部姿态结果，返回当前帧检测到的主要手势事件（只返回置信度最高的一个）。
    /// - Parameter hand: 手部关键点数据
    /// - Returns: 手势事件（若无手势则 type 为 .none，confidience 为 0）
    func analyze(_ hand: HandPoseResult) -> GestureEvent {
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

        // --- grab (抓取) --- 可近似使用 fist 的更强条件? 暂时以 fist 替代，待调整
        // 略

        // --- peace (剪刀) 等预留，需要额外关键点
        // 略

        // --- swipe 手势暂时省略 (需要跟踪帧间位移)

        // --- 冷却与去重 ---
        if let event = bestEvent {
            // 如果冷却时间内出现相同事件且在 0.3s 内，标记为重复
            let isRepeat: Bool
            if event.gestureType == lastEventType && now.timeIntervalSince(lastEventTime) < cooldownInterval {
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
            lastEventType = event.gestureType
            lastEventTime = now
            return finalEvent
        }

        // 无手势
        let noneEvent = GestureEvent(gestureType: .none, confidence: 0, timestamp: now, handPosition: handPos, velocity: velocity)
        lastEventType = .none
        lastEventTime = now
        return noneEvent
    }
}
