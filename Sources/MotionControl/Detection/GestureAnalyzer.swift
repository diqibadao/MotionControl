import Foundation
import CoreGraphics

/// 手势事件，包含类型、置信度和时间戳。
public struct GestureEvent {
    /// 手势类型。
    public let gestureType: GestureType
    /// 置信度（0.0 – 1.0）。
    public let confidence: Double
    /// 事件产生的时间戳。
    public let timestamp: Date

    public init(gestureType: GestureType, confidence: Double, timestamp: Date = Date()) {
        self.gestureType = gestureType
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// 支持的手势类型（仅包含手部手势）。
public enum GestureType: String, Codable, CaseIterable {
    case pinch
    case point
    case openPalm
    case fist
    case thumbsUp
    case ok
}

/// 手部手势分析引擎，通过手部关键点检测产生手势事件。
public class GestureAnalyzer {

    // MARK: - 可调阈值
    /// 捏合手势的距离阈值（归一化坐标）
    private let pinchDistanceThreshold: CGFloat = 0.05
    /// 张开手掌时指尖到手腕的最小距离阈值
    private let openPalmDistanceThreshold: CGFloat = 0.15
    /// 握拳时指尖到手腕的最大距离阈值
    private let fistDistanceThreshold: CGFloat = 0.08
    /// 翘拇指时拇指到手腕的最小距离阈值
    private let thumbsUpMinDist: CGFloat = 0.12
    /// 指点手势中食指长度相对于其他手指平均长度的最小比例
    private let pointRatio: CGFloat = 1.5

    public init() {}

    /// 分析单只手的姿态结果，返回检测到的手势事件列表。
    /// - Parameter hand: 手部关键点数据（归一化坐标 0~1）。
    /// - Returns: 当前帧检测到的手势事件数组。
    public func analyze(_ hand: HandPoseResult) -> [GestureEvent] {
        var events: [GestureEvent] = []
        let now = Date()

        // --- 捏合手势（pinch） ---
        if let thumb = hand.thumbTip, let index = hand.indexTip {
            let dist = hypot(thumb.x - index.x, thumb.y - index.y)
            if dist < pinchDistanceThreshold {
                let confidence = max(0.0, 1.0 - Double(dist / pinchDistanceThreshold))
                events.append(GestureEvent(gestureType: .pinch,
                                           confidence: confidence,
                                           timestamp: now))
            }
        }

        // --- 指点手势（point） ---
        // 要求食指伸直，其他手指弯曲
        if let indexTip = hand.indexTip,
           let indexPIP = hand.indexPIP,
           let middleTip = hand.middleTip,
           let ringTip = hand.ringTip,
           let littleTip = hand.littleTip,
           let wrist = hand.wrist {
            let indexLen = hypot(indexTip.x - wrist.x, indexTip.y - wrist.y)
            let middleLen = hypot(middleTip.x - wrist.x, middleTip.y - wrist.y)
            let ringLen = hypot(ringTip.x - wrist.x, ringTip.y - wrist.y)
            let littleLen = hypot(littleTip.x - wrist.x, littleTip.y - wrist.y)

            let avgOther = (middleLen + ringLen + littleLen) / 3.0
            // 食指长度明显大于其他手指，并且自身达到一定长度
            if indexLen > avgOther * pointRatio && indexLen > openPalmDistanceThreshold {
                let confidence = min(1.0, Double(indexLen / (openPalmDistanceThreshold * 2)))
                events.append(GestureEvent(gestureType: .point,
                                           confidence: confidence,
                                           timestamp: now))
            }
        }

        // --- 张开手掌（openPalm） ---
        // 五指伸展，指尖到手腕的距离均大于阈值
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
            if minDist > openPalmDistanceThreshold {
                let avgDist = (thumbDist + indexDist + middleDist + ringDist + littleDist) / 5.0
                let confidence = min(1.0, Double(avgDist / (openPalmDistanceThreshold * 3)))
                events.append(GestureEvent(gestureType: .openPalm,
                                           confidence: confidence,
                                           timestamp: now))
            }
        }

        // --- 握拳（fist） ---
        // 所有手指弯曲，指尖到手腕的距离均小于阈值
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
            if maxDist < fistDistanceThreshold {
                let avgDist = (thumbDist + indexDist + middleDist + ringDist + littleDist) / 5.0
                let confidence = max(0.0, 1.0 - Double(avgDist / fistDistanceThreshold))
                events.append(GestureEvent(gestureType: .fist,
                                           confidence: confidence,
                                           timestamp: now))
            }
        }

        // --- 翘拇指（thumbsUp） ---
        // 拇指伸直，其余手指弯曲
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
            if thumbDist > thumbsUpMinDist && otherMax < fistDistanceThreshold {
                let confidence = min(1.0, Double(thumbDist / (thumbsUpMinDist * 3)))
                events.append(GestureEvent(gestureType: .thumbsUp,
                                           confidence: confidence,
                                           timestamp: now))
            }
        }

        // 后续可扩展 OK 手势等（需要更多关键点信息）

        return events
    }
}
