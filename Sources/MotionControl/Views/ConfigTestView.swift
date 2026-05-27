import SwiftUI

/// 底部测试区，显示实时手势、注视、嘴型数据及捏合阈值对比条。
struct ConfigTestView: View {
    @State private var gesture: GestureType = .none
    @State private var gaze: CGPoint = .zero
    @State private var mouthRatio: Float = 0.0
    @State private var pinchDist: CGFloat = 0.0
    @State private var pinchThreshold: CGFloat = 0.05

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("手势: \(gesture.displayName)")
                Spacer()
                Text("注视: (\(Int(gaze.x)), \(Int(gaze.y)))")
            }
            HStack {
                Text("嘴型开合比: \(String(format: "%.2f", mouthRatio))")
                Spacer()
            }
            HStack {
                Text("捏合距离:")
                Slider(value: $pinchDist, in: 0...0.1)
                Text(String(format: "%.3f", pinchDist))
            }
            HStack {
                Text("捏合阈值:")
                Slider(value: $pinchThreshold, in: 0.01...0.1)
                Text(String(format: "%.3f", pinchThreshold))
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
