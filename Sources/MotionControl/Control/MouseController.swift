import Foundation
import CoreGraphics

/// 鼠标控制器，使用 CGEvent 模拟鼠标操作。
class MouseController {

    init() {}

    /// 移动光标至指定位置（屏幕坐标）
    func moveCursor(to point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    /// 左键单击
    func leftClick(at point: CGPoint? = nil) {
        let pos = point ?? NSEvent.mouseLocation
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: pos, mouseButton: .left) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: pos, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 右键单击
    func rightClick(at point: CGPoint? = nil) {
        let pos = point ?? NSEvent.mouseLocation
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                                 mouseCursorPosition: pos, mouseButton: .right) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                               mouseCursorPosition: pos, mouseButton: .right) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 双击
    func doubleClick(at point: CGPoint? = nil) {
        let pos = point ?? NSEvent.mouseLocation
        for _ in 0..<2 {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                     mouseCursorPosition: pos, mouseButton: .left) else { return }
            guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                   mouseCursorPosition: pos, mouseButton: .left) else { return }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// 拖拽（按下左键，移动，松开）
    func drag(from start: CGPoint, to end: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: start, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                           mouseCursorPosition: end, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: end, mouseButton: .left) else { return }
        up.post(tap: .cghidEventTap)
    }

    /// 滚动（deltaY >0 向上，<0 向下）
    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                   wheelCount: 2, wheel1: deltaY, wheel2: deltaX,
                                   wheel3: 0) else { return }
        scroll.post(tap: .cghidEventTap)
    }
}
