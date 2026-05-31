import CoreGraphics
import Foundation

class CursorController {

    // MARK: - 属性

    /// 当前光标位置（未经注视偏移的平滑位置）
    var currentPosition: CGPoint = .zero

    /// EMA 平滑因子，数值越大平滑效果越强
    var smoothingFactor: CGFloat = 7

    /// 手指是否激活（方向控制模式）
    private(set) var fingerActive = false

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

    /// 更新手指指向的目标位置，并用自适应平滑移动到该位置
    func updateTargetPosition(_ target: CGPoint) {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let input = "target=(\(Int(target.x)),\(Int(target.y)))"
            let output = "newPosition=(\(Int(currentPosition.x)),\(Int(currentPosition.y)))"
            EventLogger.log(event: "updateTargetPosition", frame: nil, input: input, output: output, duration: duration)
        }

        let diff = CGPoint(x: target.x - currentPosition.x,
                           y: target.y - currentPosition.y)
        let distance = sqrt(diff.x * diff.x + diff.y * diff.y)
        let factor: CGFloat = distance > 100 ? 4 : 8
        currentPosition.x += diff.x / factor
        currentPosition.y += diff.y / factor
        fingerActive = true
    }

    /// 更新光标位置（基于指尖位移）
    /// - Parameters:
    ///   - tip: 当前帧指尖归一化坐标 (0~1)
    ///   - lastTip: 上一帧指尖归一化坐标
    ///   - screenSize: 屏幕尺寸
    ///   - sensitivity: 灵敏度倍率
    func updateWithDelta(tip: CGPoint, lastTip: CGPoint, screenSize: CGSize, sensitivity: Float) {
        // X: 镜像（摄像头画面镜像，用户左=画面右=tip增大，需要反向）
        let dx = (lastTip.x - tip.x) * screenSize.width * CGFloat(sensitivity)
        let dy = (tip.y - lastTip.y) * screenSize.height * CGFloat(sensitivity)
        
        // 死区：小于 5px 的移动忽略（防 jitter）
        guard abs(dx) > 5 || abs(dy) > 5 else { return }
        
        let dist = sqrt(dx*dx + dy*dy)
        let factor: CGFloat = dist < 30 ? 1 : (dist < 200 ? 3 : 6)
        currentPosition.x += dx / factor
        currentPosition.y += dy / factor
        
        currentPosition.x = max(0, min(currentPosition.x, screenSize.width))
        currentPosition.y = max(0, min(currentPosition.y, screenSize.height))
        
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

    // MARK: - 光标计算

    /// 计算最终光标位置（加入注视偏移并限制在屏幕范围内）
    /// - Parameters:
    ///   - frameId: 当前帧 ID（用于日志串联）
    func computeCursor(screenSize: CGSize, sensitivity: Float, dt: Double = 1.0 / 30.0, frameId: Int? = nil) -> CGPoint {
        var cursor = currentPosition
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let input = "screenSize=(\(Int(screenSize.width)),\(Int(screenSize.height))) sensitivity=\(sensitivity)"
            let output = "cursor=(\(Int(cursor.x)),\(Int(cursor.y)))"
            EventLogger.log(event: "computeCursor", frame: frameId, input: input, output: output, duration: duration)
        }
        
        // 迟滞磁吸：三态状态机（接入 35px，释放 50px）
        if let scanner = uiScanner {
            let magnetStart = CFAbsoluteTimeGetCurrent()
            var snapElement: UIElementInfo? = nil
            var snapCenter: CGPoint? = nil
            
            switch magnetState {
            case .idle:
                // IDLE：检查是否有近距元素可以锁定
                if let near = scanner.nearElement {
                    let center = CGPoint(x: near.frame.midX, y: near.frame.midY)
                    let dx = center.x - cursor.x
                    let dy = center.y - cursor.y
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < 35 {
                        // 咔哒锁定
                        magnetState = .snap(near)
                        cursor = center
                    }
                }
                
            case .snap(let element):
                let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                let dx = center.x - cursor.x
                let dy = center.y - cursor.y
                let dist = sqrt(dx * dx + dy * dy)
                
                if dist > 50 {
                    // 超出释放阈值 → 自由
                    magnetState = .idle
                } else {
                    // 锁定中：80% 拉向中心（阻力感），20% 跟随手指
                    cursor.x += (center.x - cursor.x) * 0.8
                    cursor.y += (center.y - cursor.y) * 0.8
                    snapElement = element
                    snapCenter = center
                }
            }
            
            let magnetDuration = (CFAbsoluteTimeGetCurrent() - magnetStart) * 1000
            let magnetStateStr: String
            switch magnetState {
            case .idle: magnetStateStr = "idle"
            case .snap: magnetStateStr = "snap"
            }
            let magnetInput = "state=\(magnetStateStr) nearElement=\(scanner.nearElement != nil)"
            let magnetOutput = "snapCenter=(\(Int(snapCenter?.x ?? -1)),\(Int(snapCenter?.y ?? -1)))"
            EventLogger.log(event: "computeCursor.magnet", frame: frameId, input: magnetInput, output: magnetOutput, duration: magnetDuration)
            
            if let center = snapCenter {
                print("[MAGNET] SNAP to (\(Int(center.x)),\(Int(center.y)))")
            }
        }

        // 加入注视偏移（防钳死：仅当光标距离屏幕边缘超过5px才施偏移）
        if gazeActive {
            if cursor.x > 5 && cursor.x < screenSize.width - 5 {
                cursor.x += CGFloat(yawOffset) * screenSize.width * 0.05
            }
            if cursor.y > 5 && cursor.y < screenSize.height - 5 {
                cursor.y += CGFloat(pitchOffset) * screenSize.height * 0.05
            }
        }

        // 限制在屏幕内
        cursor.x = max(0, min(cursor.x, screenSize.width))
        cursor.y = max(0, min(cursor.y, screenSize.height))

        return cursor
    }
}
