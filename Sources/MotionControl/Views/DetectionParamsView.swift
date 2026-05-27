import SwiftUI

/// 检测参数滑条视图
struct DetectionParamsView: View {
    @State private var gestureSensitivity: Double = 0.5     // 0~1
    @State private var mouseSpeed: Double = 0.5
    @State private var gazeFollowEnabled = true

    var body: some View {
        Form {
            Section("手势灵敏度") {
                Slider(value: $gestureSensitivity, in: 0...1, step: 0.05)
                Text("值: \(gestureSensitivity, specifier: "%.2f")")
            }
            Section("鼠标控制") {
                Slider(value: $mouseSpeed, in: 0...1, step: 0.05)
                Text("速度: \(mouseSpeed, specifier: "%.2f")")
            }
            Section("注视追踪") {
                Toggle("启用注视追踪", isOn: $gazeFollowEnabled)
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }
}
