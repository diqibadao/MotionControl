import SwiftUI

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
    
    var body: some View {
        HSplitView {
            VStack {
                Text("摄像头预览")
                    .frame(height: 360)
                StatusPanelView(state: state)
            }
            ConfigPanelView(state: state)
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
