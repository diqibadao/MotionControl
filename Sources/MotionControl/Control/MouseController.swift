import Foundation
import Cocoa
import ApplicationServices

/// 鼠标控制器，使用 CGEvent 模拟鼠标操作。
class MouseController {

    init() {}

    /// 移动光标至指定位置（屏幕坐标）
    func moveCursor(to point: CGPoint) {
        // 首先尝试使用 CGWarpMouseCursorPosition 强制移动光标（不需要辅助权限？）
        CGWarpMouseCursorPosition(point)

        // 权限检查仅用于日志，不阻止后续的 CGEvent 尝试
        if !AXIsProcessTrusted() {
            EventLogger.log(event: "moveCursor", frame: nil,
                            input: "point: \(point)",
                            output: "Accessibility permission not granted", duration: nil)
        }
        EventLogger.log(event: "mouseMoved", frame: nil,
                        input: "point: \(point)", output: "", duration: nil)
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 左键单击
    func leftClick(at point: CGPoint? = nil) {
        guard AXIsProcessTrusted() else {
            EventLogger.log(event: "leftClick", frame: nil,
                            input: "point: \(point ?? NSEvent.mouseLocation)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let pos = point ?? NSEvent.mouseLocation
        EventLogger.log(event: "leftClick", frame: nil,
                        input: "point: \(pos)", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: pos, mouseButton: .left) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: pos, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 右键单击
    func rightClick(at point: CGPoint? = nil) {
        guard AXIsProcessTrusted() else {
            EventLogger.log(event: "rightClick", frame: nil,
                            input: "point: \(point ?? NSEvent.mouseLocation)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let pos = point ?? NSEvent.mouseLocation
        EventLogger.log(event: "rightClick", frame: nil,
                        input: "point: \(pos)", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                                 mouseCursorPosition: pos, mouseButton: .right) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                               mouseCursorPosition: pos, mouseButton: .right) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 双击
    func doubleClick(at point: CGPoint? = nil) {
        guard AXIsProcessTrusted() else {
            EventLogger.log(event: "doubleClick", frame: nil,
                            input: "point: \(point ?? NSEvent.mouseLocation)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let pos = point ?? NSEvent.mouseLocation
        EventLogger.log(event: "doubleClick", frame: nil,
                        input: "point: \(pos)", output: "", duration: nil)
        for _ in 0..<2 {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                     mouseCursorPosition: pos, mouseButton: .left) else { return }
            guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                   mouseCursorPosition: pos, mouseButton: .left) else { return }
            down.post(tap: CGEventTapLocation.cghidEventTap)
            up.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    /// 拖拽（按下左键，移动，松开）
    func drag(from start: CGPoint, to end: CGPoint) {
        guard AXIsProcessTrusted() else {
            EventLogger.log(event: "drag", frame: nil,
                            input: "start: \(start), end: \(end)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        EventLogger.log(event: "drag", frame: nil,
                        input: "start: \(start), end: \(end)", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: start, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                           mouseCursorPosition: end, mouseButton: .left)
        move?.post(tap: CGEventTapLocation.cghidEventTap)
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: end, mouseButton: .left) else { return }
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 滚动（deltaY >0 向上，<0 向下）
    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        guard AXIsProcessTrusted() else {
            EventLogger.log(event: "scroll", frame: nil,
                            input: "deltaY: \(deltaY), deltaX: \(deltaX)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        EventLogger.log(event: "scroll", frame: nil,
                        input: "deltaY: \(deltaY), deltaX: \(deltaX)", output: "", duration: nil)
        guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                   wheelCount: 2, wheel1: deltaY, wheel2: deltaX,
                                   wheel3: 0) else { return }
        scroll.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
