import SwiftUI

struct StatusPanelView: View {
    @Bindable var state: SystemState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Label("实时状态", systemImage: "info.circle")
                    .font(.title2)
                Divider()
                HStack {
                    Text("FPS:")
                    Text(String(format: "%.1f", state.currentFPS))
                }
                HStack {
                    Text("手势:")
                    Text(state.currentGesture)
                }
                HStack {
                    Text("置信度:")
                    Text(String(format: "%.2f", state.gestureConfidence))
                }
                HStack {
                    Text("注视:")
                    Text(state.gazeActive ? "\(Int(state.gazePosition.x)), \(Int(state.gazePosition.y))" : "—")
                }
                HStack {
                    Text("嘴型:")
                    Text(state.mouthStatus == .open ? "open" : state.mouthStatus == .closed ? "closed" : "unknown")
                }
                HStack {
                    Text("语音:")
                    Text(state.voiceState)
                }
            }
            .font(.caption)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
        }
        .frame(maxHeight: 300)
    }
}
