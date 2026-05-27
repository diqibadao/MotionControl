import Foundation
import CoreGraphics

/// 代表一个检测到的手势事件。
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

/// 支持的手势类型枚举。
public enum GestureType: String, Codable, CaseIterable {
    case blink
    case winkLeft
    case winkRight
    case mouthOpen
    case headNod
    case headShake
    case smile
    case eyebrowRaise
}

/// 手势分析引擎，通过面部特征点检测结果产生手势事件。
public class GestureAnalyzer {
    // MARK: - 可调阈值
    private let blinkThreshold: CGFloat = 0.2          // 眼睛纵横比（EAR）低于此值视为闭合
    private let mouthOpenThreshold: CGFloat = 0.6       // 嘴巴纵横比（MAR）高于此值视为张开
    private let nodAngleThreshold: Double = 0.3        // 弧度
    private let shakeAngleThreshold: Double = 0.3

    public init() {}

    /// 分析单个人脸特征点结果，返回检测到的手势事件列表。
    /// - Parameter face: FaceMeshDetector 返回的人脸特征点数据。
    /// - Returns: 当前帧检测到的手势事件数组。
    public func analyze(_ face: FaceResult) -> [GestureEvent] {
        var events: [GestureEvent] = []
        let now = Date()

        // --- 眼睛手势 ---
        if let leftEye = face.leftEye, let rightEye = face.rightEye {
            let leftEAR = computeEAR(leftEye)
            let rightEAR = computeEAR(rightEye)

            // 双眼闭合 → 眨眼
            if leftEAR < blinkThreshold && rightEAR < blinkThreshold {
                let blink = GestureEvent(gestureType: .blink,
                                         confidence: Double(1.0 - (leftEAR + rightEAR) / (2 * blinkThreshold)),
                                         timestamp: now)
                events.append(blink)
            }

            // 左眼闭合、右眼睁开 → 左眼 wink
            if leftEAR < blinkThreshold && rightEAR >= blinkThreshold {
                let winkLeft = GestureEvent(gestureType: .winkLeft,
                                            confidence: Double(1.0 - leftEAR / blinkThreshold),
                                            timestamp: now)
                events.append(winkLeft)
            }

            // 右眼闭合、左眼睁开 → 右眼 wink
            if rightEAR < blinkThreshold && leftEAR >= blinkThreshold {
                let winkRight = GestureEvent(gestureType: .winkRight,
                                             confidence: Double(1.0 - rightEAR / blinkThreshold),
                                             timestamp: now)
                events.append(winkRight)
            }
        }

        // --- 嘴巴手势 ---
        if let outerLips = face.outerLips {
            let mar = computeMAR(outerLips)
            if mar > mouthOpenThreshold {
                let mouthOpen = GestureEvent(gestureType: .mouthOpen,
                                             confidence: Double(mar - mouthOpenThreshold) / Double(1.0 - mouthOpenThreshold),
                                             timestamp: now)
                events.append(mouthOpen)
            }
        }

        // --- 头部手势（利用欧拉角） ---
        if let pitch = face.pitch?.doubleValue,
           let yaw = face.yaw?.doubleValue {
            // 点头：pitch 变化（正值表示低头）
            if abs(pitch) > nodAngleThreshold {
                let nod = GestureEvent(gestureType: .headNod,
                                       confidence: min(Double(abs(pitch)) / (2 * nodAngleThreshold), 1.0),
                                       timestamp: now)
                events.append(nod)
            }

            // 摇头：yaw 变化（正值表示右转）
            if abs(yaw) > shakeAngleThreshold {
                let shake = GestureEvent(gestureType: .headShake,
                                         confidence: min(Double(abs(yaw)) / (2 * shakeAngleThreshold), 1.0),
                                         timestamp: now)
                events.append(shake)
            }
        }

        // 其他手势（微笑、眉毛上抬等）可在后续扩展中添加
        // 目前暂未实现

        return events
    }

    // MARK: - 私有辅助方法

    /// 计算眼睛纵横比（Eye Aspect Ratio, EAR）。
    /// 典型的眼睑点数组包含 6 个点，本方法使用其中的首尾与上下四点。
    private func computeEAR(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 6 else { return 1.0 }

        // 假设索引：0 = 左外眼角，1 = 上眼睑中部，3 = 右外眼角，4 = 下眼睑中部
        let left = points[0]
        let right = points[3]
        let top = points[1]
        let bottom = points[4]

        let verticalDist = hypot(top.x - bottom.x, top.y - bottom.y)
        let horizontalDist = hypot(left.x - right.x, left.y - right.y)

        guard horizontalDist > 0 else { return 1.0 }
        return verticalDist / (2 * horizontalDist)
    }

    /// 计算嘴巴纵横比（Mouth Aspect Ratio, MAR）。
    /// 外唇点集通常包含 12 个点，这里使用左、右、上、下四个代表性点。
    private func computeMAR(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 10 else { return 0.0 }

        // 假设索引：0 = 左嘴角，6 = 右嘴角，3 = 上唇中部，9 = 下唇中部
        let left = points[0]
        let right = points[6]
        let top = points[3]
        let bottom = points[9]

        let verticalDist = hypot(top.x - bottom.x, top.y - bottom.y)
        let horizontalDist = hypot(left.x - right.x, left.y - right.y)

        guard horizontalDist > 0 else { return 0.0 }
        return verticalDist / horizontalDist
    }
}
