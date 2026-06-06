import Foundation
import CoreGraphics
import Testing
@testable import MotionControl

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
