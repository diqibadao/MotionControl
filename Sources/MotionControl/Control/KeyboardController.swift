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
            sendKeyCombo(Self.kVK_UpArrow, flags: .maskControl) // Ctrl+Up
        case .launchpad:
            // Launchpad 没有标准全局快捷键，通过 open 命令启动
            let process = Process()
            process.launchPath = "/usr/bin/open"
            process.arguments = ["/System/Applications/Launchpad.app"]
            process.launch()
        case .showDesktop:
            sendKeyCombo(0x67, flags: []) // F11
        case .appExpose:
            sendKeyCombo(Self.kVK_DownArrow, flags: .maskControl) // Ctrl+Down
        case .nextSpace:
            sendKeyCombo(Self.kVK_RightArrow, flags: .maskControl) // Ctrl+Right
        case .prevSpace:
            sendKeyCombo(Self.kVK_LeftArrow, flags: .maskControl) // Ctrl+Left
        case .openQuickLook:
            pressKey(Self.kVK_Space) // Space
        case .screenshot:
            sendKeyCombo(0x13, flags: [.maskCommand, .maskShift]) // Cmd+Shift+3
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
