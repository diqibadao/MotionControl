import SwiftUI

struct DetectionParamsView: View {
    @ObservedObject var configManager = ConfigManager.shared
    
    // 保持原有的局部状态（未要求与配置绑定）
    @State private var gestureSensitivity: Double = 0.5
    @State private var mouseSpeed: Double = 0.5
    
    // 注视跟随开关 – 绑定到 ConfigManager
    private var gazeEnabledBinding: Binding<Bool> {
        Binding(
            get: { configManager.currentConfig.gazeEnabled },
            set: { configManager.currentConfig.gazeEnabled = $0 }
        )
    }
    
    // 注视灵敏度 – 绑定到 ConfigManager（Float -> Double 转换）
    private var gazeSensitivityBinding: Binding<Double> {
        Binding(
            get: { Double(configManager.currentConfig.gazeSensitivity) },
            set: { configManager.currentConfig.gazeSensitivity = Float($0) }
        )
    }

    var body: some View {
        Form {
            Section("手势灵敏度") {
                Slider(value: $gestureSensitivity, in: 0...1, step: 0.05)
                Text("值: \(gestureSensitivity, specifier: "%.2f")")
            }
            
            Section("鼠标速度") {
                Slider(value: $mouseSpeed, in: 0...1, step: 0.05)
                Text("值: \(mouseSpeed, specifier: "%.2f")")
            }
            
            Section("注视跟随") {
                Toggle("启用注视跟随", isOn: gazeEnabledBinding)
            }
            
            Section("注视灵敏度") {
                Slider(value: gazeSensitivityBinding, in: 0...1, step: 0.05)
                Text("值: \(gazeSensitivityBinding.wrappedValue, specifier: "%.2f")")
            }
        }
        .padding()
    }
}
