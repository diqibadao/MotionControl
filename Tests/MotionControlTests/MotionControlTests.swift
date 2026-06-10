import Foundation
import CoreGraphics
import Testing
@testable import MotionControl

// MARK: - 离线回放测试框架

/// 回放历史手部轨迹，用当前 CursorController 算法重算光标位置
struct ReplayTest {
    /// 解析 trace 文件，返回 (hand, originalTarget, timestamp)
    static func parseTrace(from path: String) -> [(hand: CGPoint, originalTarget: CGPoint, t: TimeInterval)] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var frames: [(CGPoint, CGPoint, TimeInterval)] = []
        var t: TimeInterval = 0
        for line in content.components(separatedBy: "\n") {
            // 提取 hand=(hx,hy)
            guard let hs = line.range(of: "hand=(") else { continue }
            let afterH = line[hs.upperBound...]
            guard let he = afterH.firstIndex(of: ")") else { continue }
            let hc = afterH[..<he].split(separator: ",")
            guard hc.count >= 2, let hx = Double(hc[0]), let hy = Double(hc[1]) else { continue }

            // 提取 target=(tx,ty)
            let afterHParen = afterH[he...]
            guard let ts = afterHParen.range(of: "target=(") else { continue }
            let afterT = afterHParen[ts.upperBound...]
            guard let te = afterT.firstIndex(of: ")") else { continue }
            let tc = afterT[..<te].split(separator: ",")
            guard tc.count >= 2, let tx = Double(tc[0]), let ty = Double(tc[1]) else { continue }

            frames.append((CGPoint(x: hx, y: hy), CGPoint(x: tx, y: ty), t))
            t += 1.0 / 24.0
        }
        return frames
    }

    /// 从 trace 数据反推原点
    static func estimateOrigin(from frames: [(hand: CGPoint, originalTarget: CGPoint, t: TimeInterval)],
                               screen: CGSize, gain: Float) -> CGPoint {
        // 取 target 最接近屏幕中心的 20 帧，反推手位置 = 原点
        let screenCX = screen.width / 2
        let screenCY = screen.height / 2
        let nearCenter = frames.sorted {
            let d1 = sqrt(pow($0.originalTarget.x - screenCX, 2) + pow($0.originalTarget.y - screenCY, 2))
            let d2 = sqrt(pow($1.originalTarget.x - screenCX, 2) + pow($1.originalTarget.y - screenCY, 2))
            return d1 < d2
        }.prefix(20)
        let avgHX = nearCenter.reduce(0) { $0 + $1.hand.x } / CGFloat(nearCenter.count)
        let avgHY = nearCenter.reduce(0) { $0 + $1.hand.y } / CGFloat(nearCenter.count)
        return CGPoint(x: avgHX, y: avgHY)
    }

    /// 执行回放，返回 (日志行, target误差数组)
    static func replay(trace frames: [(hand: CGPoint, originalTarget: CGPoint, t: TimeInterval)],
                       screen: CGSize = CGSize(width: 1920, height: 1080),
                       gain: Float = 2.0) -> (log: [String], targetErrors: [CGFloat]) {
        let controller = CursorController()
        var logLines: [String] = []
        var errors: [CGFloat] = []

        // 固定原点，重置滤波器
        controller.handAppeared()
        let calibFrames = min(30, frames.count)

        // 预热30帧（滤波器从校准原点收敛到手部轨迹）
        let warmupStart = calibFrames
        let warmupEnd = min(warmupStart + 30, frames.count)
        for i in warmupStart..<warmupEnd {
            controller.updateWithAbsolutePosition(
                handCenter: frames[i].hand, screenSize: screen, gain: gain, handedness: .unknown)
        }

        // 正式回放 + 验证（跳过校准和预热帧）
        for i in warmupEnd..<frames.count {
            let frame = frames[i]
            controller.updateWithAbsolutePosition(
                handCenter: frame.hand, screenSize: screen, gain: gain, handedness: .unknown)
            for _ in 0..<5 {
                let nx = controller.currentPosition.x + (controller.targetPosition.x - controller.currentPosition.x) * 0.65
                let ny = controller.currentPosition.y + (controller.targetPosition.y - controller.currentPosition.y) * 0.65
                controller.currentPosition = CGPoint(x: nx, y: ny)
            }
            let cursor = controller.computeCursor(screenSize: screen, sensitivity: 1.0)

            let error = sqrt(pow(controller.targetPosition.x - frame.originalTarget.x, 2) +
                            pow(controller.targetPosition.y - frame.originalTarget.y, 2))
            errors.append(error)

            logLines.append("[CURSOR-ABS] handSide=unknown hand=(\(String(format:"%.3f",frame.hand.x)),\(String(format:"%.3f",frame.hand.y))) filter=(\(String(format:"%.3f",frame.hand.x)),\(String(format:"%.3f",frame.hand.y))) target=(\(String(format:"%.0f",controller.targetPosition.x)),\(String(format:"%.0f",controller.targetPosition.y))) cursor=(\(String(format:"%.0f",cursor.x)),\(String(format:"%.0f",cursor.y)))")
        }
        return (logLines, errors)
    }
}

@Test func replayTrace_comparesOutput() throws {
    let baseDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let traceDir = baseDir.appendingPathComponent("Docs/logs").path
    let files = try FileManager.default.contentsOfDirectory(atPath: traceDir)
    let traceFiles = files.filter { $0.hasSuffix("-trace.tsv") }.sorted()
    guard !traceFiles.isEmpty else {
        print("⏭ 跳过：无 trace"); return
    }

    for traceFile in traceFiles {
        let tracePath = "\(traceDir)/\(traceFile)"
        let frames = ReplayTest.parseTrace(from: tracePath)
        guard frames.count > 50 else {
            print("⏭ 跳过：\(traceFile) 数据不足(\(frames.count)帧)"); continue
        }

        print("\n🎬 回放: \(traceFile) (\(frames.count)帧)")

        let (logLines, errors) = ReplayTest.replay(trace: frames)
        let versionName = traceFile.replacingOccurrences(of: "-trace.tsv", with: "")

        // 写入 /tmp 供即时分析
        let tmpLog = "/tmp/replay-\(versionName).log"
        try logLines.joined(separator: "\n").write(toFile: tmpLog, atomically: true, encoding: .utf8)

        // 自动入库：写入 Docs/logs/ 供版本追踪
        let archiveLog = "\(traceDir)/\(versionName)-replay.log"
        try logLines.joined(separator: "\n").write(toFile: archiveLog, atomically: true, encoding: .utf8)

        let avgError = errors.reduce(0, +) / CGFloat(errors.count)
        let maxError = errors.max() ?? 0
        print("✅ 回放完成: \(logLines.count)帧")
        print("📐 target偏差: avg=\(String(format:"%.0f", avgError))px max=\(String(format:"%.0f", maxError))px")
        print("📊 指标: ./scripts/analyze-cursor-log.sh \(tmpLog)")
        print("📦 入库: \(archiveLog)")
    }
    print("\n💡 同一trace对比不同版本 → 纯算法差异")
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

// MARK: - 固定原点测试

@Test func fixedOrigin_isConstant() {
    let controller = CursorController()
    #expect(controller.origin.x == 0.5, "X原点固定为画面正中")
    #expect(controller.origin.y == 0.4, "Y原点固定在画面偏上40%")
    // 多次调用不应改变原点
    controller.handAppeared()
    #expect(controller.origin.x == 0.5, "handAppeared 不应改变原点")
    controller.handDisappeared()
    #expect(controller.origin.x == 0.5, "handDisappeared 不应改变原点")
}

// MARK: - 左右手方向测试（左右手统一映射，无需翻转 X）

@Test func leftAndRightHand_sameDirectionMapping() {
    let controller = CursorController()
    controller.handAppeared()

    // 右手：handCenter>origin → cursorX = screenCX - offset → 光标左移
    controller.updateWithAbsolutePosition(
        handCenter: CGPoint(x: 0.6, y: 0.4),
        screenSize: CGSize(width: 1920, height: 1080),
        gain: 2.0, handedness: .right
    )
    let rightTargetX = controller.targetPosition.x
    #expect(rightTargetX < 960, "右手：handCenter>origin → 光标左移")

    // 左手：与右手一致，handCenter>origin → 光标左移（无需镜像补偿）
    // 摄像头镜像下，手物理右移→摄像头X↓→offset负→cursorX=screenCX-(-)→光标右移 ✓
    // 手物理左移→摄像头X↑→offset正→cursorX=screenCX-(+)→光标左移 ✓
    controller.updateWithAbsolutePosition(
        handCenter: CGPoint(x: 0.6, y: 0.4),
        screenSize: CGSize(width: 1920, height: 1080),
        gain: 2.0, handedness: .left
    )
    #expect(controller.targetPosition.x < 960, "左手：与右手一致，handCenter>origin → 光标左移")
    #expect(abs(controller.targetPosition.x - rightTargetX) < 1.0, "左右手相同手位应产生相同光标位置")
}
