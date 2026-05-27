import SwiftUI

/// 手势映射列表视图，支持编辑、新增和恢复默认。
public struct GestureMappingView: View {
    @State private var mappings: [GestureType: SystemCommand] = [
        .pinch: .missionControl,
        .point: .launchpad
    ]
    @State private var selectedGesture: GestureType = .pinch
    @State private var selectedCommand: SystemCommand = .missionControl

    public var body: some View {
        VStack(alignment: .leading) {
            Text("手势映射")
                .font(.title2)
            List {
                ForEach(Array(mappings.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { gesture in
                    HStack {
                        Text(gesture.displayName)
                        Spacer()
                        Text(mappings[gesture]?.displayName ?? "")
                    }
                }
            }
            Divider()
            HStack {
                Picker("手势", selection: $selectedGesture) {
                    ForEach(GestureType.allCases, id: \.self) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                Picker("命令", selection: $selectedCommand) {
                    ForEach(SystemCommand.allCases, id: \.self) { cmd in
                        Text(cmd.displayName).tag(cmd)
                    }
                }
                Button("添加/修改") {
                    mappings[selectedGesture] = selectedCommand
                }
                Button("恢复默认") {
                    // 默认映射
                    mappings = [
                        .pinch: .missionControl,
                        .point: .launchpad
                    ]
                }
            }
            .padding()
        }
        .padding()
    }
}
