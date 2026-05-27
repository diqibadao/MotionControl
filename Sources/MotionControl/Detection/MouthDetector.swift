import Foundation
import CoreGraphics

/// 嘴部状态枚举
public enum MouthStatus: String {
    case open
    case closed
    case unknown
}

/// 嘴部事件，包含当前状态、确认状态、开合比、边缘触发。
public struct MouthEvent {
    public let status: MouthStatus
    public let confirmedStatus: MouthStatus
    public let ratio: Float     // 0.0 ~ 1.0
    public let justOpened: Bool
    public let justClosed: Bool

    public init(status: MouthStatus, confirmedStatus: MouthStatus, ratio: Float,
                justOpened: Bool, justClosed: Bool) {
        self.status = status
        self.confirmedStatus = confirmedStatus
        self.ratio = ratio
        self.justOpened = justOpened
        self.justClosed = justClosed
    }
}

/// 嘴部检测器，通过 FaceResult 中嘴部关键点计算开合比。
public class MouthDetector {

    // MARK: - 参数
    // 开合比阈值，大于此值认为张开
    private let openThreshold: Float = 0.6
    // 滞回区间，低于此值认为闭合
    private let closeThreshold: Float = 0.4
    // 防抖帧数
    private let debounceFrames: Int = 3

    // 内部状态
    private var history: [MouthStatus] = []
    private var lastConfirmed: MouthStatus = .unknown
    private var previousStatus: MouthStatus = .unknown

    public init() {}

    /// 检测嘴部状态
    /// - Parameter face: 人脸结果（包含嘴部关键点）
    /// - Returns: 嘴部事件
    public func detect(from face: FaceResult) -> MouthEvent {
        // 计算开合比：依据上嘴唇和下嘴唇关键点间的平均距离除以嘴唇宽度
        let ratio: Float
        if let points = face.mouthPoints, points.count >= 8 {
            // 假设 points[0] 左嘴角, points[4] 右嘴角 -> 宽度
            let leftCorner = points[0]
            let rightCorner = points[4]
            let width = hypot(rightCorner.x - leftCorner.x, rightCorner.y - leftCorner.y)
            guard width > 0 else {
                ratio = 0.0
            }
            // 上嘴唇中点 points[2] 下嘴唇中点 points[6]
            let upperLip = points[2]
            let lowerLip = points[6]
            let height = hypot(lowerLip.x - upperLip.x, lowerLip.y - upperLip.y)
            ratio = Float(height / width)
        } else {
            ratio = 0.0
        }

        // 滞回判断
        let currentStatus: MouthStatus
        if ratio > openThreshold {
            currentStatus = .open
        } else if ratio < closeThreshold {
            currentStatus = .closed
        } else {
            currentStatus = (lastConfirmed == .open) ? .open : .closed
        }

        // 防抖
        history.append(currentStatus)
        if history.count > debounceFrames {
            history.removeFirst()
        }

        // 统计历史中出现最多的状态
        let openCount = history.filter { $0 == .open }.count
        let closedCount = history.filter { $0 == .closed }.count
        let stableStatus: MouthStatus
        if openCount > history.count / 2 {
            stableStatus = .open
        } else if closedCount > history.count / 2 {
            stableStatus = .closed
        } else {
            stableStatus = lastConfirmed
        }

        // 边缘触发
        let justOpened = (stableStatus == .open && lastConfirmed != .open)
        let justClosed = (stableStatus == .closed && lastConfirmed != .closed)

        let confirmedStatus = stableStatus
        lastConfirmed = confirmedStatus
        previousStatus = currentStatus

        return MouthEvent(status: currentStatus,
                          confirmedStatus: confirmedStatus,
                          ratio: ratio,
                          justOpened: justOpened,
                          justClosed: justClosed)
    }
}
