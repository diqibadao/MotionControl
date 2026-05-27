import SwiftUI

/// 语音设置视图
public struct VoiceSettingsView: View {
    @State private var voiceEnabled = true
    @State private var mouthOpenThreshold: Float = 0.6
    @State private var mouthCloseThreshold: Float = 0.4
    @State private var showPrivacyInfo = false

    public var body: some View {
        Form {
            Section("语音控制") {
                Toggle("启用语音输入", isOn: $voiceEnabled)
            }
            Section("嘴型阈值") {
                HStack {
                    Text("张开阈值")
                    Slider(value: $mouthOpenThreshold, in: 0.1...1.0, step: 0.05)
                }
                HStack {
                    Text("闭合阈值")
                    Slider(value: $mouthCloseThreshold, in: 0.1...1.0, step: 0.05)
                }
            }
            Section("隐私说明") {
                Button("查看隐私说明") {
                    showPrivacyInfo.toggle()
                }
                .sheet(isPresented: $showPrivacyInfo) {
                    VStack(spacing: 16) {
                        Text("语音数据仅本地处理，不会上传至云端。")
                        Button("关闭") { showPrivacyInfo = false }
                    }
                    .padding()
                }
            }
        }
        .padding()
    }
}
