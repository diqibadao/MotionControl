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
    
    @State private var cameraService = CameraService()
    @State private var detectionPipeline = DetectionPipeline()
    
    var body: some View {
        HSplitView {
            VStack {
                Text("摄像头预览")
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
            // 启动摄像头
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
