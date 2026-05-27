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
    
    @State private var handKeypoints: [CGPoint] = []
    @State private var faceKeypoints: [CGPoint] = []
    @State private var commandTriggeredAt: Date = .distantPast
    
    var body: some View {
        HSplitView {
            VStack {
                ZStack(alignment: .topLeading) {
                    CameraPreviewView(session: cameraService.cameraSession)
                    CameraOverlayView(
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
            // 将摄像头输出连接到检测管道
            cameraService.onSampleBuffer = { [weak detectionPipeline] sampleBuffer in
                detectionPipeline?.didOutputFrame(sampleBuffer)
            }
            // 手势事件 → 执行映射动作
            let mouseCtrl = MouseController()
            let keyboardCtrl = KeyboardController()
            detectionPipeline.onGesture = { event in
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
                // 追加的状态同步
                state.currentGesture = event.gestureType.displayName
                state.gestureConfidence = Float(event.confidence)
                state.handPosition = event.handPosition
                state.handDetected = event.gestureType != .none
                if event.gestureType != .none && !event.isRepeat {
                    commandTriggeredAt = Date()
                }
            }
            // 其它回调
            detectionPipeline.onMouthEvent = { event in
                state.mouthStatus = event.status
                state.mouthOpenRatio = event.ratio
            }
            detectionPipeline.onGaze = { gazeResult in
                state.gazeActive = true
                state.gazePosition = gazeResult.screenPosition
            }
            detectionPipeline.onHandResult = { handResult in
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
            }
            detectionPipeline.onFaceResult = { faceResult in
                var points: [CGPoint] = []
                if let contour = faceResult.faceContour { points.append(contentsOf: contour) }
                if let leftEye = faceResult.leftEye { points.append(contentsOf: leftEye) }
                if let rightEye = faceResult.rightEye { points.append(contentsOf: rightEye) }
                if let leftPupil = faceResult.leftPupil { points.append(leftPupil) }
                if let rightPupil = faceResult.rightPupil { points.append(rightPupil) }
                if let outerLips = faceResult.outerLips { points.append(contentsOf: outerLips) }
                if let innerLips = faceResult.innerLips { points.append(contentsOf: innerLips) }
                faceKeypoints = points
            }
            cameraService.onFPSUpdate = { fps, count in
                state.currentFPS = fps
                state.frameCount = count
            }
            detectionPipeline.start()
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
