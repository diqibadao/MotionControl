// Sources/MotionControl/Views/GestureMappingView.swift

import SwiftUI

/// 手势映射列表视图，支持编辑、新增和恢复默认。
/// ・列表行按 GestureType.allCases 顺序显示，不依赖字典 keys
/// ・Picker 使用 ActionType（而非 SystemCommand）
/// ・映射数据以 [GestureType.rawValue: GestureAction] 形式存储
struct GestureMappingView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    /// 当前手势映射字典（rawValue -> GestureAction）
    @State private var mappings: [String: GestureAction] = [:]

    /// 列表中被选中的手势（高亮行）
    @State private var selectedGesture: GestureType? = nil

    /// Picker 中当前选择的手势
    @State private var pickerGesture: GestureType = .pinch

    /// Picker 中当前选择的动作类型（ActionType）
    @State private var pickerAction: ActionType = .leftClick

    var body: some View {
        VStack(alignment: .leading) {
            Text("手势映射")
                .font(.title2)

            // 映射列表（按 GestureType 顺序）
            List {
                ForEach(GestureType.allCases, id: \.self) { gesture in
                    HStack {
                        Text(gesture.displayName)
                        Spacer()
                        Text(mappings[gesture.rawValue]?.actionName ?? "")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedGesture = gesture
                        pickerGesture = gesture
                        // 若已有映射则使用其 actionType，否则保持默认
                        pickerAction = mappings[gesture.rawValue]?.actionType ?? .leftClick
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
                Picker("动作", selection: $pickerAction) {
                    ForEach(ActionType.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                // 按钮文字根据是否有映射决定
                let gestureExists = mappings[pickerGesture.rawValue] != nil
                let buttonLabel = gestureExists ? "修改" : "添加"

                Button(buttonLabel) {
                    // 构造新的 GestureAction
                    let newAction = GestureAction(
                        id: UUID(),
                        gesture: pickerGesture,
                        actionType: pickerAction,
                        actionValue: nil,
                        actionName: pickerAction.displayName,
                        systemIcon: nil,
                        isEnabled: true
                    )
                    mappings[pickerGesture.rawValue] = newAction
                    // 写回 ConfigManager
                    configManager.currentConfig.gestureMapping = mappings
                    configManager.objectWillChange.send()
                }

                Button("恢复默认") {
                    // 提供一组示例默认映射（可根据需求调整）
                    let defaultMappings: [String: GestureAction] = [
                        GestureType.pinch.rawValue: GestureAction(
                            gesture: .pinch,
                            actionType: .scroll,
                            actionName: ActionType.scroll.displayName
                        ),
                        GestureType.point.rawValue: GestureAction(
                            gesture: .point,
                            actionType: .leftClick,
                            actionName: ActionType.leftClick.displayName
                        )
                    ]
                    mappings = defaultMappings
                    configManager.currentConfig.gestureMapping = defaultMappings
                    configManager.objectWillChange.send()

                    // 重置 Picker 状态
                    if let first = GestureType.allCases.first {
                        pickerGesture = first
                        pickerAction = defaultMappings[first.rawValue]?.actionType ?? .leftClick
                    }
                }
            }
            .padding()
        }
        .padding()
        .onAppear {
            // 从 ConfigManager 加载映射
            mappings = configManager.currentConfig.gestureMapping

            // 初始化第一个手势的 Picker
            if let first = GestureType.allCases.first {
                pickerGesture = first
                pickerAction = mappings[first.rawValue]?.actionType ?? .leftClick
            }
        }
    }
}
