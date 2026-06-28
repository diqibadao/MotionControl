import SwiftUI
import AVFoundation
import ServiceManagement

/// MotionControl 应用入口。
/// 通过摄像头 + MediaPipe 实现手势识别、视线追踪和嘴部检测，
/// 将肢体动作映射为鼠标/键盘操作。
@main
struct MotionControlApp: App {
    @State private var state = SystemState()
    
    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
        }
    }
}

/// 主界面，包含摄像头预览、状态叠加层和配置面板。
/// 通过 DetectionPipeline 串联手势/视线/嘴部检测，
/// 实时更新 UI 状态并执行对应的鼠标/键盘动作。
struct ContentView: View {
    @Bindable var state: SystemState
    
    private let cameraService = CameraService()
    private let detectionPipeline = DetectionPipeline()
    private let mouseCtrl = MouseController()
    private let keyboardCtrl = KeyboardController()
    private let cursorController = CursorController()
    private let uiScanner = UIElementScanner()
    private let debugOverlay = DebugOverlay()

    @State private var handKeypoints: [CGPoint] = []
    @State private var faceKeypoints: [CGPoint] = []
    @State private var commandTriggeredAt: Date = .distantPast
    @State private var frameGenTimer: Timer? = nil   // 120fps 补帧定时器
    @State private var overlayTimer: Timer? = nil    // 蒙层刷新定时器
    @State private var lostFrameCount = 0            // 连续丢失手掌的帧数
    
    var body: some View {
        HSplitView {
            VStack {
                ZStack(alignment: .topLeading) {
                    CameraPreviewView(
                        session: cameraService.cameraSession,
                        handKeypoints: handKeypoints,
                        faceKeypoints: faceKeypoints,
                        isCommandActive: Date().timeIntervalSince(commandTriggeredAt) < 1.0,
                        frameSize: cameraService.currentFrameSize ?? .zero
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "FPS: %.1f", state.currentFPS))
                        Text("手势: \(state.currentGesture)  \(String(format: "%.2f", state.gestureConfidence))")
                        Text("模式: \(state.fingerMode)")
                        Text("嘴型: \(state.mouthStatus == .open ? "open" : state.mouthStatus == .closed ? "closed" : "unknown")")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .padding(8)
                }
                Spacer()
            }
            ConfigPanelView(state: state)
        }
        .onAppear {
            EventLogger.startLogFile()
            cameraService.onSampleBuffer = { [weak detectionPipeline] sampleBuffer in
                detectionPipeline?.didOutputFrame(sampleBuffer)
            }
            // 手势事件 → 动作映射管线
            detectionPipeline.onGesture = { event in
                // 食指弯曲(.indexTap)=左键单击，其他手势按配置映射
#if DEBUG
                print("[DEBUG] onGesture called, type=\(event.gestureType)")
#endif
                guard !event.isRepeat else { return }
                let config = ConfigManager.shared.currentConfig
                guard let action = config.gestureMapping[event.gestureType.rawValue], action.isEnabled else { return }
                switch action.actionType {
                case .mouseMove:
                    let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                    let x = (event.handPosition.x / 640.0) * screen.width * CGFloat(config.mouseSensitivity)
                    let y = (event.handPosition.y / 480.0) * screen.height * CGFloat(config.mouseSensitivity)
                    mouseCtrl.moveCursor(to: CGPoint(x: x, y: y))
                case .leftClick: mouseCtrl.leftClick()
                case .rightClick: mouseCtrl.rightClick()
                case .doubleClick: mouseCtrl.doubleClick()
                case .scrollUp: mouseCtrl.scroll(deltaY: Int32(max(1.0, event.confidence * 10)))
                case .scrollDown: mouseCtrl.scroll(deltaY: -Int32(max(1.0, event.confidence * 10)))
                case .keyPress: keyboardCtrl.pressKey(CGKeyCode(action.actionValue.flatMap { UInt16($0) } ?? 36))
                case .systemCommand:
                    if let cmd = action.actionValue.flatMap({ SystemCommand(rawValue: $0) }) {
                        keyboardCtrl.executeSystemCommand(cmd)
                    }
                default: break
                }
                state.currentGesture = event.gestureType.displayName
                state.gestureConfidence = Float(event.confidence)
                state.handPosition = event.handPosition
                state.handDetected = event.gestureType != .none
                if event.gestureType != .none && !event.isRepeat {
                    commandTriggeredAt = Date()
                }
            }
            // 嘴型回调
            detectionPipeline.onMouthEvent = { event in
                state.mouthStatus = event.status
                state.mouthOpenRatio = event.ratio
            }
            // 注视回调（接收 GazeEstimate）
            detectionPipeline.onGaze = { gazeEstimate in
#if DEBUG
                print("[DEBUG] onGaze called, yaw=\(gazeEstimate.yawOffset)")
#endif
                // 鼠标位置埋点：记录当前系统光标实际位置
#if DEBUG
                print("[MOUSE] location=\(NSEvent.mouseLocation)")
#endif
                state.gazeActive = gazeEstimate.hasFace
                state.gazePosition = CGPoint(x: CGFloat(gazeEstimate.yawOffset),
                                             y: CGFloat(gazeEstimate.pitchOffset))
                cursorController.updateGazeOffset(yaw: gazeEstimate.yawOffset,
                                                  pitch: gazeEstimate.pitchOffset,
                                                  hasFace: gazeEstimate.hasFace)
            }
            // 手部结果回调（关键点 + 方向控制模式）
            detectionPipeline.onHandResult = { handResult, dt in
#if DEBUG
                print("[DEBUG] onHandResult called, hasTip=\(handResult?.indexTip != nil)")
#endif
                guard let handResult = handResult else {
                    handKeypoints = []
                    cursorController.handDisappeared()
                    return
                }
                var points: [CGPoint] = []
                if let p = handResult.wrist { points.append(p) }
                if let p = handResult.thumbTip { points.append(p) }
                if let p = handResult.thumbIP { points.append(p) }
                if let p = handResult.thumbMP { points.append(p) }
                if let p = handResult.indexTip { points.append(p) }
                if let p = handResult.indexDIP { points.append(p) }
                if let p = handResult.indexPIP { points.append(p) }
                if let p = handResult.indexMCP { points.append(p) }
                if let p = handResult.middleTip { points.append(p) }
                if let p = handResult.middleDIP { points.append(p) }
                if let p = handResult.middlePIP { points.append(p) }
                if let p = handResult.middleMCP { points.append(p) }
                if let p = handResult.ringTip { points.append(p) }
                if let p = handResult.ringDIP { points.append(p) }
                if let p = handResult.ringPIP { points.append(p) }
                if let p = handResult.ringMCP { points.append(p) }
                if let p = handResult.littleTip { points.append(p) }
                if let p = handResult.littleDIP { points.append(p) }
                if let p = handResult.littlePIP { points.append(p) }
                if let p = handResult.littleMCP { points.append(p) }
                handKeypoints = points

                // 原始数据埋点：每帧关键点质量（暂时关闭避免 String(format:) 异常）
                let kp = handResult
                EventLogger.log(event: "KEYPOINTS", frame: nil, input: "handSide=\(kp.handSide) palmCenter=\(kp.palmCenter?.x ?? 0),\(kp.palmCenter?.y ?? 0)", output: "", duration: nil)

                // 固定原点绝对位置映射（Leap Motion InteractionBox 方案）
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                let config = ConfigManager.shared.currentConfig

                // ⚡ SPIKE: 用 indexMCP 做光标，但只在「单食指伸直」模式激活
                let mode = handResult.fingerMode
                state.fingerMode = mode.rawValue
                if let center = handResult.indexMCP, handResult.confidence > 0.15, mode == .cursor, !detectionPipeline.cursorFrozen {
                    lostFrameCount = 0
                    // 手首次出现时重置滤波器
                    if !cursorController.fingerActive {
                        cursorController.handAppeared()
                    }
                    cursorController.updateWithAbsolutePosition(
                        handCenter: center,
                        screenSize: screen,
                        gain: config.mouseSensitivity,
                        handedness: handResult.handSide
                    )
                    let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0, dt: CGFloat(dt))
                    mouseCtrl.moveCursor(to: finalCursor)
                } else {
                    lostFrameCount += 1
                    if lostFrameCount > 15 {
                        cursorController.handDisappeared()
                        lostFrameCount = 0
                    }
                }
            }
            // 人脸结果回调（关键点）
            detectionPipeline.onFaceResult = { faceResult in
                guard let faceResult = faceResult else { faceKeypoints = []; return }
                var points: [CGPoint] = []
                if let contour = faceResult.faceContour { points.append(contentsOf: contour) }
                if let leftEye = faceResult.leftEye { points.append(contentsOf: leftEye) }
                if let rightEye = faceResult.rightEye { points.append(contentsOf: rightEye) }
                if let leftPupil = faceResult.leftPupil { points.append(leftPupil) }
                if let rightPupil = faceResult.rightPupil { points.append(rightPupil) }
                if let outerLips = faceResult.outerLipsAbsolute { points.append(contentsOf: outerLips) }
                if let innerLips = faceResult.innerLipsAbsolute { points.append(contentsOf: innerLips) }
                faceKeypoints = points
            }
            cameraService.onFPSUpdate = { fps, count in
                state.currentFPS = fps
                state.frameCount = count
            }
            detectionPipeline.start()
            detectionPipeline.startGazeCalibration()
            
            // 60fps 补帧定时器：Lerp 追赶检测帧设定的 targetPosition
            // 每帧只移动一小步（lerp=0.35），即使目标很远也不会跳变
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0/120.0, repeats: true) { _ in
                guard cursorController.fingerActive else { return }
                let lerp: CGFloat = 0.65  // 更快追赶目标，减少滞后感
                let pos = cursorController.currentPosition
                let target = cursorController.targetPosition
                let newX = pos.x + (target.x - pos.x) * lerp
                let newY = pos.y + (target.y - pos.y) * lerp
                cursorController.currentPosition = CGPoint(x: newX, y: newY)
                mouseCtrl.moveCursor(to: CGPoint(x: newX, y: newY))
            }
            // 保证补帧定时器不被 UI 事件阻塞
            RunLoop.current.add(timer, forMode: .common)
            self.frameGenTimer = timer
            
            CameraService.shared = cameraService
            let configuredDeviceID = ConfigManager.shared.currentConfig.cameraDeviceID
            cameraService.start(withDeviceID: configuredDeviceID.isEmpty ? nil : configuredDeviceID)
            // 注册 AXHelper LaunchAgent（首次需用户授权）
            registerAXHelper()
            uiScanner.start()
            cursorController.uiScanner = uiScanner
            if ConfigManager.shared.currentConfig.debugOverlayEnabled {
                debugOverlay.start()
            }
            // 调试蒙层刷新定时器
            let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard ConfigManager.shared.currentConfig.debugOverlayEnabled else { return }
                let cursor = NSEvent.mouseLocation
                var bestCenter: CGPoint? = nil
                var bestDist = CGFloat.greatestFiniteMagnitude
                let screenH = NSScreen.main?.frame.height ?? 1080
                for el in uiScanner.cachedElements {
                    let cx = el.frame.midX
                    let cy = el.frame.midY  // 统一坐标系：el.frame 和 cursor 均为 Quartz
                    let dx = cx - cursor.x
                    let dy = cy - cursor.y
                    let d = sqrt(dx*dx + dy*dy)
                    if d < bestDist { bestDist = d; bestCenter = CGPoint(x: cx, y: cy) }
                }
                debugOverlay.update(elements: uiScanner.cachedElements, cursor: cursor, nearestCenter: bestCenter)
            }
            RunLoop.current.add(t, forMode: .common)
            self.overlayTimer = t
        }
        .onDisappear {
            cameraService.stop()
            cameraService.onSampleBuffer = nil
            uiScanner.stop()
            frameGenTimer?.invalidate()
            frameGenTimer = nil
            overlayTimer?.invalidate()
            overlayTimer = nil
            debugOverlay.stop()
            EventLogger.stopLogFile()
        }
        .task {
            let perms = await PermissionManager.shared.checkAll()
            state.cameraGranted = perms.camera
            state.micGranted = perms.mic
            state.speechGranted = perms.speech
            state.accessibilityGranted = perms.accessibility
        }
    }

    /// 启动 AXHelper：优先 LaunchAgent，签名失败则委托 uiScanner spawn
    private func registerAXHelper() {
        // 1. 尝试 LaunchAgent 注册
        do {
            let agent = SMAppService.agent(plistName: "com.motioncontrol.axhelper")
            try agent.register()
            EventLogger.log(event: "axHelper", frame: nil, input: "launchAgent registered", output: "status=\(agent.status.rawValue)", duration: 0)
            return
        } catch {
            EventLogger.log(event: "axHelper", frame: nil, input: "register failed, fallback to spawn", output: error.localizedDescription, duration: 0)
        }
        // 2. 签名失败 → 委托 UIElementScanner spawn AXHelper
        uiScanner.spawnAXHelper()
    }
}
