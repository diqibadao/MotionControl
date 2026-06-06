import Foundation
import CoreGraphics
import Testing
@testable import MotionControl

// MARK: - 离线回放测试框架

/// 回放历史手部轨迹，用当前 CursorController 算法重算光标位置
struct ReplayTest {
    /// 解析 trace 文件中的 hand 位置，保留原始时间戳
    static func parseHandPositions(from path: String) -> [(CGPoint, TimeInterval)] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var frames: [(CGPoint, TimeInterval)] = []
        var t: TimeInterval = 0
        for line in content.components(separatedBy: "\n") {
            guard let handStart = line.range(of: "hand=(") else { continue }
            let rest = line[handStart.upperBound...]
            guard let handEnd = rest.firstIndex(of: ")") else { continue }
            let coordStr = rest[..<handEnd]
            let coords = coordStr.split(separator: ",")
            guard coords.count >= 2,
                  let hx = Double(coords[0]), let hy = Double(coords[1]) else { continue }
            frames.append((CGPoint(x: hx, y: hy), t))
            t += 1.0 / 24.0  // 模拟 24fps 检测帧率
        }
        return frames
    }

    /// 执行回放，返回日志行
    static func replay(trace frames: [(CGPoint, TimeInterval)],
                       screen: CGSize = CGSize(width: 1920, height: 1080),
                       gain: Float = 2.0) -> [String] {
        let controller = CursorController()
        var logLines: [String] = []
        let calibFrames = min(15, frames.count)

        // 阶段1：校准（模拟手刚入画面的 0.5s）
        controller.startCalibration()
        for i in 0..<calibFrames {
            let (hand, _) = frames[i]
            if controller.accumulateOrigin(hand) { break }  // 校准完成
        }
        // 如果没完成（样本不够），强制等足时间
        if controller.calibrationState != .tracking {
            Thread.sleep(forTimeInterval: 0.55)
            _ = controller.accumulateOrigin(frames[calibFrames-1].0)
        }

        // 阶段2：跟踪（只记录跟踪帧，跳过校准帧）
        for i in calibFrames..<frames.count {
            let (hand, _) = frames[i]
            controller.updateWithAbsolutePosition(
                handCenter: hand, screenSize: screen,
                gain: gain, handedness: .unknown
            )
            // 模拟 120Hz timer: 检测帧间隔~42ms → 约5次 lerp 追赶
            for _ in 0..<5 {
                let nx = controller.currentPosition.x + (controller.targetPosition.x - controller.currentPosition.x) * 0.65
                let ny = controller.currentPosition.y + (controller.targetPosition.y - controller.currentPosition.y) * 0.65
                controller.currentPosition = CGPoint(x: nx, y: ny)
            }
            let cursor = controller.computeCursor(screenSize: screen, sensitivity: 1.0)
            logLines.append("[CURSOR-ABS] hand=(\(String(format:"%.3f",hand.x)),\(String(format:"%.3f",hand.y))) filter=(\(String(format:"%.3f",hand.x)),\(String(format:"%.3f",hand.y))) target=(\(String(format:"%.0f",controller.targetPosition.x)),\(String(format:"%.0f",controller.targetPosition.y))) cursor=(\(String(format:"%.0f",cursor.x)),\(String(format:"%.0f",cursor.y)))")
        }
        return logLines
    }
}

@Test func replayTrace_comparesOutput() throws {
    let baseDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let traceDir = baseDir.appendingPathComponent("Docs/logs").path
    let files = try FileManager.default.contentsOfDirectory(atPath: traceDir)
    guard let traceFile = files.first(where: { $0.hasSuffix("-trace.tsv") }) else {
        print("⏭ 跳过回放：无 trace 文件"); return
    }
    let tracePath = "\(traceDir)/\(traceFile)"
    let frames = ReplayTest.parseHandPositions(from: tracePath)
    guard frames.count > 20 else {
        print("⏭ 跳过回放：trace 数据不足(\(frames.count)帧)"); return
    }

    print("回放: \(traceFile) (\(frames.count)帧) → 当前算法 v\(String(describing: Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?"))")

    let logLines = ReplayTest.replay(trace: frames)
    let replayLog = "/tmp/replay-\(traceFile.replacingOccurrences(of: "-trace.tsv", with: "")).log"
    try logLines.joined(separator: "\n").write(toFile: replayLog, atomically: true, encoding: .utf8)
    print("✅ 回放完成: \(logLines.count) 帧 → \(replayLog)")
    print("📊 运行: ./scripts/analyze-cursor-log.sh \(replayLog)")
}

// MARK: - 1€ Filter 单元测试

@Test func oneEuroFilter_initialValue_returnedUnchanged() {
    var filter = OneEuroFilter()
    let result = filter.filter(0.5, time: 1.0)
    #expect(result == 0.5, "初始值应原样返回")
}

@Test func oneEuroFilter_stationarySignal_jitterSuppressed() {
    var filter = OneEuroFilter(fcMin: 1.0, beta: 0.007, fcD: 1.0)

    // 先喂几个值建立基线
    _ = filter.filter(0.500, time: 1.0)
    _ = filter.filter(0.500, time: 1.1)
    _ = filter.filter(0.500, time: 1.2)

    // 加一个小的抖动（模拟手部震颤 ~0.003）
    let jittered = filter.filter(0.503, time: 1.3)

    // 抖动应该被衰减，输出应接近 0.500
    #expect(abs(jittered - 0.500) < 0.003, "微震颤应被过滤掉")
}

@Test func oneEuroFilter_fastMovement_lightFiltering() {
    var filter = OneEuroFilter(fcMin: 1.0, beta: 0.007, fcD: 1.0)

    _ = filter.filter(0.500, time: 1.0)
    _ = filter.filter(0.500, time: 1.1)

    // 快速大位移（模拟手快速移动，delta=0.05）
    let result = filter.filter(0.550, time: 1.2)

    // 快速移动时滤波较轻，但仍有单帧滞后（1€ Filter 特性）
    // 0.05 跳变经过 1 帧滤波后大约滞后 0.02-0.04
    #expect(abs(result - 0.550) < 0.04, "快速移动应有轻度滤波，但不应滞后太多")
}

@Test func oneEuroFilter_slowMovement_moderateFiltering() {
    var filter = OneEuroFilter(fcMin: 1.0, beta: 0.007, fcD: 1.0)

    _ = filter.filter(0.500, time: 1.0)
    _ = filter.filter(0.500, time: 1.1)

    // 慢速位移（模拟手缓慢移动，delta=0.01）
    let result = filter.filter(0.510, time: 1.2)

    // 慢速应适度滤波
    #expect(abs(result - 0.510) < 0.008, "慢速移动应有适度滤波")
}

@Test func oneEuroFilter_reset_clearsState() {
    var filter = OneEuroFilter()

    _ = filter.filter(0.500, time: 1.0)
    _ = filter.filter(0.600, time: 1.1)

    filter.reset()

    // Reset 后第一帧应原样返回
    let result = filter.filter(0.700, time: 2.0)
    #expect(result == 0.700, "Reset 后首帧应原样返回")
}

@Test func oneEuroFilter_zeroTimeDelta_handledGracefully() {
    var filter = OneEuroFilter()

    _ = filter.filter(0.500, time: 1.0)
    // 同一时间戳（dt=0）不应崩溃
    let result = filter.filter(0.600, time: 1.0)
    #expect(result > 0, "零时间差不应崩溃")
}

// MARK: - 原点校准测试

@Test func originCalibration_averagesSamples() {
    let controller = CursorController()
    controller.startCalibration()

    // 喂 10 个不同的手部位置
    for i in 0..<10 {
        _ = controller.accumulateOrigin(CGPoint(x: 0.4 + CGFloat(i) * 0.01, y: 0.5))
    }

    // 第一个 call 开始校准，state 应转为 .calibrating
    #expect(controller.calibrationState == .calibrating, "应处于校准中")

    // 0.5s 后且 >=5 个样本，校准应完成
    Thread.sleep(forTimeInterval: 0.55)
    let done = controller.accumulateOrigin(CGPoint(x: 0.5, y: 0.5))
    #expect(done, "0.5s + 5 样本后校准应完成")
    #expect(controller.calibrationState == .tracking, "应转为跟踪状态")
}

// MARK: - 左右手同向测试（chirality 不再翻转 X）

@Test func leftAndRightHand_sameDirection() {
    let controller = CursorController()
    controller.startCalibration()
    for _ in 0..<8 {
        _ = controller.accumulateOrigin(CGPoint(x: 0.5, y: 0.4))
    }
    Thread.sleep(forTimeInterval: 0.55)
    _ = controller.accumulateOrigin(CGPoint(x: 0.5, y: 0.4))
    #expect(controller.calibrationState == .tracking)

    // 右手：handCenter>origin → cursor 左移
    controller.updateWithAbsolutePosition(
        handCenter: CGPoint(x: 0.6, y: 0.4),
        screenSize: CGSize(width: 1920, height: 1080),
        gain: 2.0, handedness: .right
    )
    #expect(controller.targetPosition.x < 960, "右手：handCenter>origin → 光标左移")

    // 左手：同向，不再镜像
    controller.updateWithAbsolutePosition(
        handCenter: CGPoint(x: 0.6, y: 0.4),
        screenSize: CGSize(width: 1920, height: 1080),
        gain: 2.0, handedness: .left
    )
    #expect(controller.targetPosition.x < 960, "左手：handCenter>origin → 光标同向左移")
}
