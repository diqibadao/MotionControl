import Foundation
import Cocoa
import ApplicationServices

/// 鼠标控制器，App Store 版使用 AX API 替代 CGEvent。
class MouseController {

    private var isTrusted: Bool { AXIsProcessTrusted() }

    init() {
        print("[AX] trusted=\(isTrusted)")
    }
    
    /// 获取光标下的 AX 元素（用于执行 Action）
    private func axElementAt(cursor: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var result: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(cursor.x), Float(cursor.y), &result)
        return err == .success ? result : nil
    }

    /// 移动光标至指定位置（屏幕坐标）
    func moveCursor(to point: CGPoint) {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let flippedPoint = CGPoint(x: point.x, y: screenHeight - point.y)
        CGWarpMouseCursorPosition(flippedPoint)
    }

    /// Cocoa → Quartz 坐标翻转
    private func flipToQuartz(_ point: CGPoint) -> CGPoint {
        let screenH = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: point.x, y: screenH - point.y)
    }

    /// 左键单击 — 通过 AX 动作执行
    func leftClick(at point: CGPoint? = nil) {
        guard isTrusted else {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            AXIsProcessTrustedWithOptions(options)
            return
        }
        let pos = flipToQuartz(point ?? NSEvent.mouseLocation)
        guard let el = axElementAt(cursor: pos) else {
            EventLogger.log(event: "leftClick", frame: nil, input: "no AX element", output: "skipped", duration: nil)
            return
        }
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        EventLogger.log(event: "leftClick", frame: nil, input: "AXPress", output: err == .success ? "ok" : "fail", duration: nil)
    }

    /// 左键按下（拖拽开始）— 拖拽功能在 App Store 版暂不支持
    func mouseDown() {
        EventLogger.log(event: "mouseDown", frame: nil, input: "unsupported in App Store version", output: "", duration: nil)
    }

    /// 左键释放（拖拽结束）
    func mouseUp() {
        EventLogger.log(event: "mouseUp", frame: nil, input: "unsupported in App Store version", output: "", duration: nil)
    }

    /// 右键单击 — 通过 AX 菜单动作执行
    func rightClick(at point: CGPoint? = nil) {
        guard isTrusted else { return }
        let pos = flipToQuartz(point ?? NSEvent.mouseLocation)
        guard let el = axElementAt(cursor: pos) else { return }
        AXUIElementPerformAction(el, kAXShowMenuAction as CFString)
    }

    /// 双击 — 两次 AX Press
    func doubleClick(at point: CGPoint? = nil) {
        guard isTrusted else { return }
        let pos = flipToQuartz(point ?? NSEvent.mouseLocation)
        guard let el = axElementAt(cursor: pos) else { return }
        AXUIElementPerformAction(el, kAXPressAction as CFString)
        usleep(100_000)
        AXUIElementPerformAction(el, kAXPressAction as CFString)
        EventLogger.log(event: "doubleClick", frame: nil, input: "AXPress×2", output: "", duration: nil)
    }

    /// 拖拽 — App Store 版暂不支持
    func drag(from start: CGPoint, to end: CGPoint) {
        EventLogger.log(event: "drag", frame: nil, input: "unsupported in App Store version", output: "", duration: nil)
    }

    /// 滚动 — 通过 AX 滚动动作执行
    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        guard isTrusted else { return }
        let cursor = flipToQuartz(NSEvent.mouseLocation)
        guard let el = axElementAt(cursor: cursor) else { return }
        let action = deltaY > 0 ? kAXIncrementAction : kAXDecrementAction
        let steps = abs(Int(deltaY))
        for _ in 0..<steps {
            AXUIElementPerformAction(el, action as CFString)
        }
        EventLogger.log(event: "scroll", frame: nil, input: "\(action) ×\(steps)", output: "", duration: nil)
    }
}
