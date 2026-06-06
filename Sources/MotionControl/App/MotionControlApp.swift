import SwiftUI
import AVFoundation

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
    
    @State private var handKeypoints: [CGPoint] = []
    @State private var faceKeypoints: [CGPoint] = []
    @State private var commandTriggeredAt: Date = .distantPast
    @State private var frameGenTimer: Timer? = nil  // 60fps 补帧定时器
    @State private var lostFrameCount = 0           // 连续丢失手掌的帧数
    
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
            cameraService.onSampleBuffer = { [weak detectionPipeline] sampleBuffer in
                detectionPipeline?.didOutputFrame(sampleBuffer)
            }
            // 手势事件 → 暂时禁用所有动作映射（纯光标测试模式）
            detectionPipeline.onGesture = { event in
                return  // 🔇 测试模式：所有手势动作已禁用，仅光标移动
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
                case .scroll: mouseCtrl.scroll(deltaY: -3)
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
                    // 手离开画面时重置校准状态
                    if cursorController.calibrationState != .idle {
                        cursorController.endCalibration()
                    }
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
                
                // 绝对位置映射 + 原点校准
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                let config = ConfigManager.shared.currentConfig
                let maxLostFrames = 15

                if let center = handResult.palmCenter, handResult.confidence > 0.15 {
                    lostFrameCount = 0

                    switch cursorController.calibrationState {
                    case .idle:
                        // 手刚出现 → 开始校准
                        cursorController.startCalibration()
                        cursorController.accumulateOrigin(center)

                    case .calibrating:
                        // 校准中 → 累积原点样本，光标不动
                        if cursorController.accumulateOrigin(center) {
                            // 校准完成，无需额外操作
                        }

                    case .tracking:
                        // 正常跟踪 → 绝对位置映射
                        cursorController.updateWithAbsolutePosition(
                            handCenter: center,
                            screenSize: screen,
                            gain: config.mouseSensitivity,
                            handedness: handResult.handSide
                        )
                    }
                } else if cursorController.calibrationState != .idle {
                    lostFrameCount += 1
                    if lostFrameCount > maxLostFrames {
                        cursorController.endCalibration()
                        lostFrameCount = 0
                    }
                }

                // 跟踪模式下移动光标（校准中/idle 不移动，解决初始跳跃）
                if cursorController.calibrationState == .tracking {
                    let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0, dt: CGFloat(dt))
#if DEBUG
                    print("[DEBUG] finalCursor=\(finalCursor)")
#endif
                    mouseCtrl.moveCursor(to: finalCursor)
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
            uiScanner.start()
            cursorController.uiScanner = uiScanner
        }
        .onDisappear {
            cameraService.stop()
            cameraService.onSampleBuffer = nil
            uiScanner.stop()
            frameGenTimer?.invalidate()
            frameGenTimer = nil
        }
        .task {
            let perms = await PermissionManager.shared.checkAll()
            state.cameraGranted = perms.camera
            state.micGranted = perms.mic
            state.speechGranted = perms.speech
            state.accessibilityGranted = perms.accessibility
        }
    }
}
