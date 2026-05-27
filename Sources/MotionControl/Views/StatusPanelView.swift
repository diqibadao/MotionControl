import SwiftUI

/// 网格状态面板，显示各项实时数据。
public struct StatusPanelView: View {
    @State private var fps: Double = 30
    @State private var currentGesture = GestureType.none
    @State private var confidence: Double = 0
    @State private var gazePoint: CGPoint = .zero
    @State private var mouthStatus: MouthStatus = .unknown
    @State private var voiceActive = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("状态面板", systemImage: "info.circle")
                .font(.title2)
            Divider()
            HStack {
                Text("FPS:")
                Text(String(format: "%.1f", fps))
            }
            HStack {
                Text("手势:")
                Text(currentGesture.displayName)
            }
            HStack {
                Text("置信度:")
                Text(String(format: "%.2f", confidence))
            }
            HStack {
                Text("注视点:")
                Text("(\(Int(gazePoint.x)), \(Int(gazePoint.y)))")
            }
            HStack {
                Text("嘴型:")
                Text(mouthStatus.rawValue)
            }
            HStack {
                Text("语音:")
                Image(systemName: voiceActive ? "mic.fill" : "mic.slash")
            }
        }
        .padding()
        .frame(width: 220)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}
