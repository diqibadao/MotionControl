import Foundation

// MARK: - 手势类型
enum GestureType: String, Codable, CaseIterable {
    case open = "OPEN"
    case point = "POINT"
    case grab = "GRAB"
    case pinch = "PINCH"
    case doublePinch = "DBL_PINCH"
    case peace = "PEACE"
    case fist = "FIST"
    case swipeLeft = "SWIPE_LEFT"
    case swipeRight = "SWIPE_RIGHT"
    case swipeUp = "SWIPE_UP"
    case swipeDown = "SWIPE_DOWN"
    case openPalm = "OPEN_PALM"
    case fivePinch = "FIVE_PINCH"
    case drag = "DRAG"
    case thumbsUp = "THUMBS_UP"
    case ok = "OK"
    case none = "NONE"
    
    var displayName: String {
        switch self {
        case .open: return "张开五指"
        case .point: return "单指点击"
        case .grab: return "拇指+食指捏合"
        case .pinch: return "拇指+中指捏合"
        case .doublePinch: return "快速两次捏合"
        case .peace: return "剪刀手"
        case .fist: return "握拳"
        case .swipeLeft: return "挥手向左"
        case .swipeRight: return "挥手向右"
        case .swipeUp: return "挥手向上"
        case .swipeDown: return "挥手向下"
        case .openPalm: return "五指张开推掌"
        case .fivePinch: return "五指捏合"
        case .drag: return "单指拖拽"
        case .thumbsUp: return "竖拇指"
        case .ok: return "OK 手势"
        case .none: return "无"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .open: return "hand.raised"
        case .point: return "hand.point.up"
        case .grab: return "hand.point.up.left"
        case .pinch: return "hand.point.up.left.fill"
        case .doublePinch: return "hand.point.up.left.fill"
        case .peace: return "hand.victory"
        case .fist: return "hand.raised.fingers.spread"
        case .swipeLeft, .swipeRight, .swipeUp, .swipeDown: return "hand.wave"
        case .openPalm: return "hand.raised"
        case .fivePinch: return "hand.pinch"
        case .drag: return "hand.draw"
        case .thumbsUp: return "hand.thumbsup"
        case .ok: return "hand.ok"
        case .none: return "questionmark"
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
    var pinchThreshold: Float = 40.0
    var gestureCooldown: Int = 200
    var doubleTapWindow: Int = 500
    var swipeVelocityThreshold: Float = 0.5
    
    // 新增阈值，供 GestureAnalyzer 读取
    var openPalmThreshold: Float = 100.0
    var fistThreshold: Float = 50.0
    var thumbsUpMinDist: Float = 80.0
    var pointRatio: Float = 1.5
    
    // 鼠标
    var mouseSensitivity: Float = 1.0
    var mouseSmoothFactor: Float = 0.4
    
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
    var cameraWidth: Int = 640
    var cameraHeight: Int = 480
    
    // 活动配置方案名
    var activeProfile: String = "日常使用"
    
    static func defaultMapping() -> [String: GestureAction] {
        var map: [String: GestureAction] = [:]
        map["OPEN"] = GestureAction(gesture: .open, actionType: .mouseMove, actionName: "鼠标移动")
        map["POINT"] = GestureAction(gesture: .point, actionType: .leftClick, actionName: "左键点击")
        map["GRAB"] = GestureAction(gesture: .grab, actionType: .leftClick, actionName: "左键点击")
        map["PINCH"] = GestureAction(gesture: .pinch, actionType: .rightClick, actionName: "右键点击")
        map["DBL_PINCH"] = GestureAction(gesture: .doublePinch, actionType: .doubleClick, actionName: "双击")
        map["PEACE"] = GestureAction(gesture: .peace, actionType: .scroll, actionName: "滚动模式")
        map["FIST"] = GestureAction(gesture: .fist, actionType: .keyPress, actionValue: "36", actionName: "回车")
        map["SWIPE_LEFT"] = GestureAction(gesture: .swipeLeft, actionType: .systemCommand, actionValue: "PREV_SPACE", actionName: "上一个桌面")
        map["SWIPE_RIGHT"] = GestureAction(gesture: .swipeRight, actionType: .systemCommand, actionValue: "NEXT_SPACE", actionName: "下一个桌面")
        map["SWIPE_UP"] = GestureAction(gesture: .swipeUp, actionType: .systemCommand, actionValue: "MISSION_CONTROL", actionName: "Mission Control")
        map["SWIPE_DOWN"] = GestureAction(gesture: .swipeDown, actionType: .systemCommand, actionValue: "APP_EXPOSE", actionName: "App Exposé")
        map["OPEN_PALM"] = GestureAction(gesture: .openPalm, actionType: .systemCommand, actionValue: "SHOW_DESKTOP", actionName: "显示桌面")
        map["FIVE_PINCH"] = GestureAction(gesture: .fivePinch, actionType: .systemCommand, actionValue: "LAUNCHPAD", actionName: "Launchpad")
        map["THUMBS_UP"] = GestureAction(gesture: .thumbsUp, actionType: .systemCommand, actionValue: "OPEN_QUICK_LOOK", actionName: "空格预览")
        return map
    }
    
    static var `default`: GestureConfig {
        GestureConfig(gestureMapping: defaultMapping())
    }
}
