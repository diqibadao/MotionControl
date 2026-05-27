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
    
    var body: some View {
        HSplitView {
            VStack {
                CameraPreviewView(session: cameraService.cameraSession)
                    .frame(height: 360)
                StatusPanelView(state: state)
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
            }
            detectionPipeline.start()
            cameraService.start()
        }
        .onDisappear {
            cameraService.stop()
            cameraService.onSampleBuffer = nil
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
