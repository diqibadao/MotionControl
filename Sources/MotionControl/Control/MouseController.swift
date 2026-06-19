import Foundation
import Cocoa
import ApplicationServices

/// 鼠标控制器，使用 CGEvent 模拟鼠标操作。
class MouseController {

    private let isTrusted = AXIsProcessTrusted()

    init() {
        print("[AX] trusted=\(isTrusted)")
    }

    /// 移动光标至指定位置（屏幕坐标）
    func moveCursor(to point: CGPoint) {
        // CGWarpMouseCursorPosition 不需要 Accessibility 权限，CGEvent post to cghidEventTap 也不需要
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0.0

        CGAssociateMouseAndMouseCursorPosition(1)  // boolean_t

        let screenHeight = NSScreen.main?.frame.height ?? 0
        let flippedPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        EventLogger.log(event: "mouseMoved", frame: nil,
                        input: "point: \(point) flipped: \(flippedPoint)", output: "", duration: nil)

        CGWarpMouseCursorPosition(flippedPoint)

        if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                   mouseCursorPosition: flippedPoint, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
    }

    /// Cocoa → Quartz 坐标翻转（NSEvent.mouseLocation 是 Cocoa 坐标系，CGEvent 需要 Quartz）
    private func flipToQuartz(_ point: CGPoint) -> CGPoint {
        let screenH = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: point.x, y: screenH - point.y)
    }

    /// 左键单击
    func leftClick(at point: CGPoint? = nil) {
        guard isTrusted else {
            EventLogger.log(event: "leftClick", frame: nil,
                            input: "point: \(point ?? NSEvent.mouseLocation)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let rawPos = point ?? NSEvent.mouseLocation
        let pos = flipToQuartz(rawPos)
        EventLogger.log(event: "leftClick", frame: nil,
                        input: "raw: \(rawPos) flipped: \(pos)", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: pos, mouseButton: .left) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: pos, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 右键单击
    func rightClick(at point: CGPoint? = nil) {
        guard isTrusted else {
            EventLogger.log(event: "rightClick", frame: nil,
                            input: "point: \(point ?? NSEvent.mouseLocation)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let rawPos = point ?? NSEvent.mouseLocation
        let pos = flipToQuartz(rawPos)
        EventLogger.log(event: "rightClick", frame: nil,
                        input: "raw: \(rawPos) flipped: \(pos)", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                                 mouseCursorPosition: pos, mouseButton: .right) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                               mouseCursorPosition: pos, mouseButton: .right) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 双击
    func doubleClick(at point: CGPoint? = nil) {
        guard isTrusted else {
            EventLogger.log(event: "doubleClick", frame: nil,
                            input: "point: \(point ?? NSEvent.mouseLocation)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let rawPos = point ?? NSEvent.mouseLocation
        let pos = flipToQuartz(rawPos)
        EventLogger.log(event: "doubleClick", frame: nil,
                        input: "raw: \(rawPos) flipped: \(pos)", output: "", duration: nil)
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
        guard isTrusted else {
            EventLogger.log(event: "drag", frame: nil,
                            input: "start: \(start), end: \(end)",
                            output: "Accessibility permission not granted", duration: nil)
            return
        }
        let flippedStart = flipToQuartz(start)
        let flippedEnd = flipToQuartz(end)
        EventLogger.log(event: "drag", frame: nil,
                        input: "start: \(start)→\(flippedStart), end: \(end)→\(flippedEnd)", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: flippedStart, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                           mouseCursorPosition: flippedEnd, mouseButton: .left)
        move?.post(tap: CGEventTapLocation.cghidEventTap)
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: flippedEnd, mouseButton: .left) else { return }
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 滚动（deltaY >0 向上，<0 向下）
    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        guard isTrusted else {
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
