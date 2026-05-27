import SwiftUI

/// 状态菜单视图（菜单栏下拉视图）
public struct StatusMenuView: View {
    @State private var detectionActive = true
    @State private var gestureEnabled = true
    @State private var voiceEnabled = true

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题
            Text("MotionControl")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            // 检测状态
            HStack {
                Text("检测状态")
                Spacer()
                Circle()
                    .fill(detectionActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            // 快捷开关
            Toggle("手势控制", isOn: $gestureEnabled)
            Toggle("语音输入", isOn: $voiceEnabled)

            Divider()

            Button("打开配置面板") {
                // 触发打开 ConfigPanelView
                openConfigPanel()
            }

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 200)
    }

    private func openConfigPanel() {
        // 使用 NSHostingController 或直接显示窗口
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ConfigPanelView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
