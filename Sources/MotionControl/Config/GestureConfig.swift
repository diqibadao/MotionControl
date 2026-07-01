import Foundation

// MARK: - 手势类型
enum GestureType: String, Codable, CaseIterable {
    case none = "NONE"
    case indexTap = "INDEX_TAP"
    case indexDoubleTap = "INDEX_DOUBLE_TAP"
    case scrollUp = "SCROLL_UP"
    case scrollDown = "SCROLL_DOWN"
    case dragStart = "DRAG_START"
    case dragEnd = "DRAG_END"
    
    var displayName: String {
        switch self {
        case .none: return "无"
        case .indexTap: return "食指单击"
        case .indexDoubleTap: return "食指双击"
        case .scrollUp: return "向上滚"
        case .scrollDown: return "向下滚"
        case .dragStart: return "拖拽开始"
        case .dragEnd: return "拖拽结束"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .none: return "questionmark"
        case .indexTap: return "hand.point.up"
        case .indexDoubleTap: return "hand.point.up.fill"
        case .scrollUp: return "arrow.up"
        case .scrollDown: return "arrow.down"
        case .dragStart: return "arrow.up.forward"
        case .dragEnd: return "arrow.up.forward"
        }
    }
}

// MARK: - 动作类型
enum ActionType: String, Codable, CaseIterable {
    case mouseMove = "MOUSE_MOVE"
    case leftClick = "LEFT_CLICK"
    case rightClick = "RIGHT_CLICK"
    case doubleClick = "DOUBLE_CLICK"
    case leftDown = "LEFT_DOWN"
    case leftUp = "LEFT_UP"
    case scroll = "SCROLL"
    case keyPress = "KEY_PRESS"
    case keyCombo = "KEY_COMBO"
    case systemCommand = "SYSTEM_COMMAND"
    // 新增动作
    case dragStart = "DRAG_START"
    case dragEnd = "DRAG_END"
    case scrollUp = "SCROLL_UP"
    case scrollDown = "SCROLL_DOWN"
    case noAction = "NO_ACTION"
    
    var displayName: String {
        switch self {
        case .mouseMove: return "鼠标移动"
        case .leftClick: return "左键点击"
        case .rightClick: return "右键点击"
        case .doubleClick: return "双击"
        case .leftDown: return "按下左键"
        case .leftUp: return "释放左键"
        case .scroll: return "滚动"
        case .keyPress: return "按键"
        case .keyCombo: return "快捷键"
        case .systemCommand: return "系统命令"
        // 新增中文名称
        case .dragStart: return "拖拽开始"
        case .dragEnd: return "拖拽结束"
        case .scrollUp: return "上滚"
        case .scrollDown: return "下滚"
        case .noAction: return "无动作"
        }
    }
}

// MARK: - 系统命令
enum SystemCommand: String, Codable, CaseIterable {
    case missionControl = "MISSION_CONTROL"
    case launchpad = "LAUNCHPAD"
    case showDesktop = "SHOW_DESKTOP"
    case appExpose = "APP_EXPOSE"
    case nextSpace = "NEXT_SPACE"
    case prevSpace = "PREV_SPACE"
    case openQuickLook = "OPEN_QUICK_LOOK"
    case screenshot = "SCREENSHOT"
    
    var displayName: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .launchpad: return "Launchpad"
        case .showDesktop: return "显示桌面"
        case .appExpose: return "App Exposé"
        case .nextSpace: return "下一个桌面"
        case .prevSpace: return "上一个桌面"
        case .openQuickLook: return "空格预览"
        case .screenshot: return "截屏"
        }
    }
}

// MARK: - 手势动作映射
struct GestureAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var gesture: GestureType
    var actionType: ActionType
    var actionValue: String?
    var actionName: String
    var systemIcon: String?
    var isEnabled: Bool = true
}

// MARK: - 全局配置
struct GestureConfig: Codable {
    // 手势映射
    var gestureMapping: [String: GestureAction]
    
    // 检测参数
    var pinchThreshold: Float = 80.0
    var gestureCooldown: Int = 200
    var doubleTapWindow: Int = 300
    var swipeVelocityThreshold: Float = 0.5
    
    // 新增阈值，供 GestureAnalyzer 读取
    var indexBendThreshold: Float = 0.02   // 食指弯曲灵敏度（Vision归一化坐标，越大越灵敏）
    var openPalmThreshold: Float = 200.0
    var fistThreshold: Float = 50.0
    var thumbsUpMinDist: Float = 80.0
    var pointRatio: Float = 1.5
    
    // 鼠标
    var mouseSensitivity: Float = 2.0  // 绝对映射 base gain（手速自适应 0.2~2.0x）
    var mouseSmoothFactor: Float = 0.4

    // 物理归一模型（Physics-Based Cursor）
    var assistEnabled: Bool = true                      // 总开关
    var debugOverlayEnabled: Bool = true                // 调试蒙层
    var phyKHand: Float = 12.0                          // 缆绳弹簧刚度
    var phyGravity: Float = 2500                        // 按钮引力强度
    var phySoftenRadius: Float = 20.0                   // 引力软化半径
    var phyGravityDecay: Float = 12.0                   // 引力衰减距离
    var phyDeadZone: Float = 3.0                        // 弹簧死区 (px)
    var blendZone: Float = 50.0                         // 权重混合区半径 (px)
    var phyDampingLow: Float = 0.98                     // 低速阻尼 (<50px/s)
    var phyDampingHigh: Float = 0.92                    // 高速阻尼 (>200px/s)
    var phySpeedLow: Float = 50                         // 低速阈值
    var phySpeedHigh: Float = 200                       // 高速阈值
    var assistBreakoutMaxSpeed: Float = 1200            // L3 完全冲破速度 (px/s)

    // 注视
    var gazeEnabled: Bool = true
    var gazeSensitivity: Float = 1.0
    var gazeSmoothFactor: Float = 0.4
    var gazeHoldTime: Int = 800
    
    // 语音
    var voiceEnabled: Bool = true
    var mouthOpenThreshold: Float = 0.6
    var mouthCloseThreshold: Float = 0.4
    var voiceDebounce: Int = 300
    
    // 摄像头
    var cameraDeviceID: String = ""
    var cameraWidth: Int = 1920
    var cameraHeight: Int = 1080
    
    // 活动配置方案名
    var activeProfile: String = "日常使用"
    
    static func defaultMapping() -> [String: GestureAction] {
        var map: [String: GestureAction] = [:]
        // 仅保留有检测代码的手势
        map["INDEX_TAP"] = GestureAction(gesture: .indexTap, actionType: .leftClick, actionName: "左键单击")
        map["INDEX_DOUBLE_TAP"] = GestureAction(gesture: .indexDoubleTap, actionType: .doubleClick, actionName: "双击")
        map["SCROLL_UP"] = GestureAction(gesture: .scrollUp, actionType: .scrollUp, actionName: "向上滚")
        map["SCROLL_DOWN"] = GestureAction(gesture: .scrollDown, actionType: .scrollDown, actionName: "向下滚")
        map["DRAG_START"] = GestureAction(gesture: .dragStart, actionType: .dragStart, actionName: "拖拽开始")
        map["DRAG_END"] = GestureAction(gesture: .dragEnd, actionType: .dragEnd, actionName: "拖拽结束")
        return map
    }
    
    static var `default`: GestureConfig {
        GestureConfig(gestureMapping: defaultMapping())
    }
}
