import Foundation
import Cocoa
import ApplicationServices

/// 鼠标控制器，使用 CGEvent 模拟鼠标操作（沙盒 + AX 权限可工作）。
class MouseController {

    private var isTrusted: Bool { AXIsProcessTrusted() }

    init() {
        checkAndRequestAXPermission()
    }

    /// 启动时检查 AX 权限，未授权则弹系统授权窗（仅弹一次）
    private func checkAndRequestAXPermission() {
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            AXIsProcessTrustedWithOptions(options)
        }
    }

    /// 移动光标至指定位置（屏幕坐标）
    func moveCursor(to point: CGPoint) {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let flippedPoint = CGPoint(x: point.x, y: screenHeight - point.y)
        CGWarpMouseCursorPosition(flippedPoint)
    }

    /// Y 轴翻转：NSEvent.mouseLocation 是 Cocoa 坐标（原点左下），CGEvent 需要 Quartz（原点左上）
    private func flipY(_ p: CGPoint) -> CGPoint {
        let h = NSScreen.main?.frame.height ?? 1080
        return CGPoint(x: p.x, y: h - p.y)
    }

    /// 左键单击
    func leftClick(at point: CGPoint? = nil) {
        let rawPos = point ?? NSEvent.mouseLocation
        let pos = flipY(rawPos)
        EventLogger.log(event: "leftClick", frame: nil, input: "pos=\(pos) trusted=\(AXIsProcessTrusted())", output: "", duration: nil)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        usleep(10_000)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 左键按下（拖拽开始）
    func mouseDown() {
        let pos = flipY(NSEvent.mouseLocation)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 左键释放（拖拽结束）
    func mouseUp() {
        let pos = flipY(NSEvent.mouseLocation)
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) else { return }
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 右键单击
    func rightClick(at point: CGPoint? = nil) {
        let rawPos = point ?? NSEvent.mouseLocation
        let pos = flipY(rawPos)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: pos, mouseButton: .right) else { return }
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: pos, mouseButton: .right) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 双击
    func doubleClick(at point: CGPoint? = nil) {
        let rawPos = point ?? NSEvent.mouseLocation
        let pos = flipY(rawPos)
        EventLogger.log(event: "doubleClick", frame: nil, input: "pos=\(pos)", output: "", duration: nil)
        for _ in 0..<2 {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left) else { continue }
            guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) else { continue }
            down.post(tap: CGEventTapLocation.cghidEventTap)
            usleep(50_000)
            up.post(tap: CGEventTapLocation.cghidEventTap)
            usleep(50_000)
        }
    }

    /// 拖拽
    func drag(from start: CGPoint, to end: CGPoint) {
        let qStart = flipY(start), qEnd = flipY(end)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: qStart, mouseButton: .left) else { return }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: qEnd, mouseButton: .left)
        move?.post(tap: CGEventTapLocation.cghidEventTap)
        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: qEnd, mouseButton: .left) else { return }
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// 滚动 — CGEvent 滚轮事件
    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        EventLogger.log(event: "scroll", frame: nil,
                        input: "deltaY: \(deltaY), deltaX: \(deltaX)", output: "", duration: nil)
        guard let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                   wheelCount: 2, wheel1: deltaY, wheel2: deltaX,
                                   wheel3: 0) else { return }
        scroll.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
