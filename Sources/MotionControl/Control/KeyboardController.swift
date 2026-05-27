import Foundation
import CoreGraphics

/// 键盘控制器，使用 CGEvent 模拟按键。
class KeyboardController {

    init() {}

    /// 按下并释放单个键
    func pressKey(_ keyCode: CGKeyCode) {
        let start = CFAbsoluteTimeGetCurrent()
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        let duration = CFAbsoluteTimeGetCurrent() - start
        EventLogger.log(event: "pressKey",
                        frame: nil,
                        input: "\(keyCode)",
                        output: "press release",
                        duration: duration)
    }

    /// 发送组合键（例如 Command+Q）
    func sendKeyCombo(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let start = CFAbsoluteTimeGetCurrent()
        guard let downFlags = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        downFlags.flags = flags
        downFlags.post(tap: .cghidEventTap)
        guard let upFlags = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        upFlags.flags = flags
        upFlags.post(tap: .cghidEventTap)
        let duration = CFAbsoluteTimeGetCurrent() - start
        EventLogger.log(event: "sendKeyCombo",
                        frame: nil,
                        input: "key:\(keyCode) flags:\(flags.rawValue)",
                        output: "combo sent",
                        duration: duration)
    }

    /// 执行系统命令（通过快捷键模拟）
    func executeSystemCommand(_ command: SystemCommand) {
        let start = CFAbsoluteTimeGetCurrent()
        switch command {
        case .missionControl:
            sendKeyCombo(0x7D, flags: .maskControl) // F3 可通过 keycode? 简化使用 Mission Control 是 control+up
            // 实际应使用 NSEvent 方法，此处仅示意
        case .launchpad:
            // Launchpad 默认是 F4
            break
        case .showDesktop:
            // F11
            sendKeyCombo(0x67, flags: [])
        case .appExpose:
            // control+down
            break
        case .nextSpace:
            sendKeyCombo(0x7C, flags: .maskControl) // right arrow
        case .prevSpace:
            sendKeyCombo(0x7B, flags: .maskControl) // left arrow
        case .openQuickLook:
            pressKey(0x31) // space
        case .screenshot:
            sendKeyCombo(0x13, flags: [.maskCommand, .maskShift]) // 3
        }
        let duration = CFAbsoluteTimeGetCurrent() - start
        EventLogger.log(event: "executeSystemCommand",
                        frame: nil,
                        input: "\(command)",
                        output: "system command executed",
                        duration: duration)
    }

    // 常用键码
    static let kVK_Space: CGKeyCode = 0x31
    static let kVK_Return: CGKeyCode = 0x24
    static let kVK_Delete: CGKeyCode = 0x33
    static let kVK_UpArrow: CGKeyCode = 0x7E
    static let kVK_DownArrow: CGKeyCode = 0x7D
    static let kVK_LeftArrow: CGKeyCode = 0x7B
    static let kVK_RightArrow: CGKeyCode = 0x7C
}
