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
                                                  pitch: gazeEstimate.pitchOffset)
            }
            // 手部结果回调（关键点 + 光标控制）
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

                // 指尖位置 → CursorController → 移动光标（仅当食指明显伸出时）
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
                let config = ConfigManager.shared.currentConfig
                if let tip = handResult.indexTip, let wrist = handResult.wrist {
                    let indexDist = hypot(tip.x - wrist.x, tip.y - wrist.y)
                    var otherDistances: [CGFloat] = []
                    if let p = handResult.thumbTip {
                        otherDistances.append(hypot(p.x - wrist.x, p.y - wrist.y))
                    }
                    if let p = handResult.middleTip {
                        otherDistances.append(hypot(p.x - wrist.x, p.y - wrist.y))
                    }
                    if let p = handResult.ringTip {
                        otherDistances.append(hypot(p.x - wrist.x, p.y - wrist.y))
                    }
                    if let p = handResult.littleTip {
                        otherDistances.append(hypot(p.x - wrist.x, p.y - wrist.y))
                    }
                    let maxOtherDist = otherDistances.max() ?? 0
                    let threshold: CGFloat = 1.2
                    if otherDistances.isEmpty || indexDist > maxOtherDist * threshold {
                        let screenX = (1.0 - tip.x) * screen.width * CGFloat(config.mouseSensitivity)
                        let screenY = (1.0 - tip.y) * screen.height * CGFloat(config.mouseSensitivity)
                        cursorController.updateHandTip(CGPoint(x: screenX, y: screenY))
                    }
                }
                // 每帧都执行一次最终的 computeCursor
                let finalCursor = cursorController.computeCursor(screenSize: screen, sensitivity: 1.0)
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
