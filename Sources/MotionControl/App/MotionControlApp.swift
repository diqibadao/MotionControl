import SwiftUI

@main
struct MotionControlApp: App {
    @State private var state = SystemState()
    
    var body: some Scene {
        MenuBarExtra("MotionControl", systemImage: "hand.raised") {
            StatusMenuView(state: state)
        }
        .menuBarExtraStyle(.menu)
        
        Window("MotionControl", id: "main") {
            ContentView(state: state)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowResizability(.contentSize)
        
        Settings {
            ConfigPanelView(state: state)
        }
    }
}

struct ContentView: View {
    @Bindable var state: SystemState
    
    var body: some View {
        HSplitView {
            // 左侧：摄像头预览 + 状态
            VStack {
                CameraPreviewView(state: state)
                StatusPanelView(state: state)
            }
            .frame(minWidth: 400)
            
            // 右侧：配置面板
            ConfigPanelView(state: state)
                .frame(minWidth: 400)
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
