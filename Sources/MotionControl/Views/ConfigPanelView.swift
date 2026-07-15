import SwiftUI

/// 配置面板主容器，三页 Tab
struct ConfigPanelView: View {
    @Bindable var state: SystemState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GestureMappingView()
                .tabItem {
                    Label("手势映射", systemImage: "hand.point.up")
                }
                .tag(0)

            DetectionParamsView()
                .tabItem {
                    Label("检测参数", systemImage: "slider.horizontal.3")
                }
                .tag(1)

            VoiceSettingsView()
                .tabItem {
                    Label("语音设置", systemImage: "mic")
                }
                .tag(2)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 350)
    }
}
