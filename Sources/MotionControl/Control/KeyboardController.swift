import Foundation
import CoreGraphics

/// 键盘控制器，使用 CGEvent 模拟按键。
public class KeyboardController {

    public init() {}

    /// 按下并释放单个键
    public func pressKey(_ keyCode: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        guard let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 发送组合键（例如 Command+Q）
    public func sendKeyCombo(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let downFlags = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        downFlags.flags = flags
        downFlags.post(tap: .cghidEventTap)
        guard let upFlags = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        upFlags.flags = flags
        upFlags.post(tap: .cghidEventTap)
    }

    /// 执行系统命令（通过快捷键模拟）
    public func executeSystemCommand(_ command: SystemCommand) {
        switch command {
        case .missionControl:
            sendKeyCombo(0x7D, flags: .maskControl) // F3 可通过 keycode? 简化使用 Mission Control 是 control+up
            // 实际应使用 NSEvent 方法，此处仅示意
        case .launchpad:
            // Launchpad 默认是 F4
            break
        case .showDesktop:
            // F11
            break
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
    }

    // 常用键码
    public static let kVK_Space: CGKeyCode = 0x31
    public static let kVK_Return: CGKeyCode = 0x24
    public static let kVK_Delete: CGKeyCode = 0x33
    public static let kVK_UpArrow: CGKeyCode = 0x7E
    public static let kVK_DownArrow: CGKeyCode = 0x7D
    public static let kVK_LeftArrow: CGKeyCode = 0x7B
    public static let kVK_RightArrow: CGKeyCode = 0x7C
}
