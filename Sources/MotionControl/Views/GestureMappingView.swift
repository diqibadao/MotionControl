// Sources/MotionControl/Views/GestureMappingView.swift

import SwiftUI

/// 手势映射列表视图，支持编辑、新增和恢复默认。
/// ・列表行可点击选中，选中后下方 Picker 自动填充手势和动作
/// ・按钮文字根据当前手势是否已有映射显示“添加”或“修改”
/// ・映射数据从 ConfigManager 读取，修改后写回 ConfigManager
struct GestureMappingView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    /// 当前手势映射字典（从 ConfigManager 加载）
    @State private var mappings: [GestureType: SystemCommand] = [:]

    /// 列表中被选中的手势（高亮行）
    @State private var selectedGesture: GestureType? = nil

    /// Picker 中当前选择的手势
    @State private var pickerGesture: GestureType = .pinch

    /// Picker 中当前选择的命令
    @State private var pickerCommand: SystemCommand = .missionControl

    var body: some View {
        VStack(alignment: .leading) {
            Text("手势映射")
                .font(.title2)

            // 映射列表
            List {
                ForEach(Array(mappings.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { gesture in
                    HStack {
                        Text(gesture.displayName)
                        Spacer()
                        Text(mappings[gesture]?.displayName ?? "")
                    }
                    .contentShape(Rectangle()) // 使整个区域可点击
                    .onTapGesture {
                        // 选中该行
                        selectedGesture = gesture
                        pickerGesture = gesture
                        pickerCommand = mappings[gesture] ?? .missionControl
                    }
                    .background(selectedGesture == gesture
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear)
                }
            }

            Divider()

            // 编辑区域
            HStack {
                Picker("手势", selection: $pickerGesture) {
                    ForEach(GestureType.allCases, id: \.self) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                Picker("命令", selection: $pickerCommand) {
                    ForEach(SystemCommand.allCases, id: \.self) { cmd in
                        Text(cmd.displayName).tag(cmd)
                    }
                }

                // 按钮文字根据是否有映射决定
                let gestureExists = mappings[pickerGesture] != nil
                let buttonLabel = gestureExists ? "修改" : "添加"

                Button(buttonLabel) {
                    // 添加或修改映射
                    mappings[pickerGesture] = pickerCommand
                    // 写回 ConfigManager
                    configManager.currentConfig.gestureMapping = mappings
                    // 显式通知 ObservableObject
                    configManager.objectWillChange.send()
                }

                Button("恢复默认") {
                    let defaultMappings: [GestureType: SystemCommand] = [
                        .pinch: .missionControl,
                        .point: .launchpad
                    ]
                    mappings = defaultMappings
                    configManager.currentConfig.gestureMapping = defaultMappings
                    configManager.objectWillChange.send()
                }
            }
            .padding()
        }
        .padding()
        .onAppear {
            // 从 ConfigManager 加载映射
            mappings = configManager.currentConfig.gestureMapping

            // 初始化 Picker 显示第一个已有的映射，若无则保持默认
            if let first = mappings.keys.sorted(by: { $0.rawValue < $1.rawValue }).first {
                pickerGesture = first
                pickerCommand = mappings[first] ?? .missionControl
            }
        }
    }
}
