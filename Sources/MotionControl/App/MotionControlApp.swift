import SwiftUI
import AVFoundation

@main
struct MotionControlApp: App {
    @State private var state = SystemState()
    
    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
        }
    }
}

struct ContentView: View {
    @Bindable var state: SystemState
    
    private let cameraService = CameraService()
    private let detectionPipeline = DetectionPipeline()
    private let mouseCtrl = MouseController()
    private let keyboardCtrl = KeyboardController()
    private let cursorController = CursorController()
    
    @State private var handKeypoints: [CGPoint] = []
    @State private var faceKeypoints: [CGPoint] = []
    @State private var commandTriggeredAt: Date = .distantPast
    
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
            // 手势事件 → 执行映射动作
            detectionPipeline.onGesture = { event in
                print("[DEBUG] onGesture called, type=\(event.gestureType)")
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
                print("[DEBUG] onGaze called, yaw=\(gazeEstimate.yawOffset)")
                state.gazeActive = gazeEstimate.hasFace
                state.gazePosition = CGPoint(x: CGFloat(gazeEstimate.yawOffset),
                                             y: CGFloat(gazeEstimate.pitchOffset))
                cursorController.updateGazeOffset(yaw: gazeEstimate.yawOffset,
                                                  pitch: gazeEstimate.pitchOffset,
                                                  hasFace: gazeEstimate.hasFace)
            }
            // 手部结果回调（关键点 + 方向控制模式）
            detectionPipeline.onHandResult = { handResult in
                print("[DEBUG] onHandResult called, hasTip=\(handResult?.indexTip != nil)")
                guard let handResult = handResult else { handKeypoints = []; return }
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
                
                // 方向控制模式
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                let config = ConfigManager.shared.currentConfig
                
                // 使用 indexPIP 或 indexDIP 作为参考点
                let pip = handResult.indexPIP ?? handResult.indexDIP
                if let tip = handResult.indexTip,
                   let pip = pip
                {
                    let dx = tip.x - pip.x
                    let dy = pip.y - tip.y   // Vision y向上，翻转
                    let length = sqrt(dx*dx + dy*dy)
                    if length > 0 {
                        let direction = CGPoint(x: dx/length, y: dy/length)
                        // 手指伸展检测：使用 handResult.fingerExtension()（需在 HandPoseResult 上实现）
                        let extensions = handResult.fingerExtension()
                        let indexExt = extensions[.index] ?? 0
                        let middleExt = extensions[.middle] ?? 0
                        let ringExt = extensions[.ring] ?? 0
                        let littleExt = extensions[.little] ?? 0
                        let thumbExt = extensions[.thumb] ?? 0
                        
                        // 调试输出扩展值
                        print("[DEBUG] extensions index=\(indexExt) middle=\(middleExt) ring=\(ringExt) little=\(littleExt) thumb=\(thumbExt)")
                        
                        let allFingers = [indexExt, middleExt, ringExt, littleExt, thumbExt]
                        let allHigh = allFingers.allSatisfy { $0 > 0.5 }
                        let otherLow = middleExt < 0.15 && ringExt < 0.15 && littleExt < 0.15 && thumbExt < 0.15
                        
                        if indexExt > 0.06 && otherLow && !allHigh {
                            // 激活方向控制
                            cursorController.updateFingerDirection(direction,
                                                                   length: length * screen.width,
                                                                   sensitivity: CGFloat(config.mouseSensitivity))
                        } else {
                            cursorController.resetCursor()
                        }
                    } else {
                        cursorController.resetCursor()
                    }
                } else {
                    cursorController.resetCursor()
                }
                
                // 每帧执行 computeCursor + moveCursor（内部根据激活状态处理）
                let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0)
                print("[DEBUG] finalCursor=\(finalCursor)")
                mouseCtrl.moveCursor(to: finalCursor)
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
            cameraService.start()
        }
        .onDisappear {
            cameraService.stop()
            cameraService.onSampleBuffer = nil
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
