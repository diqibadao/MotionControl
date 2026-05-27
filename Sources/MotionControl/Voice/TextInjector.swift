import Foundation
import AppKit

/// 文本注入器，使用辅助功能或剪贴板粘贴方式插入文字。
public class TextInjector {

    public init() {}

    /// 在当前聚焦的输入区域注入文本
    public func injectText(_ text: String) {
        // 优先使用 Accessibility API
        if let focusedElement = focusedUIElement() {
            if let value = focusedElement.attribute(kAXValueAttribute) as? String {
                focusedElement.setAttribute(kAXValueAttribute, value: value + text)
                return
            }
        }

        // 回退方案：剪贴板 + Command+V
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 模拟 Command+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v'
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func focusedUIElement() -> AXUIElement? {
        let app = NSWorkspace.shared.frontmostApplication
        guard let pid = app?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let element = focused else { return nil }
        return (element as! AXUIElement)
    }
}

// 辅助扩展
extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        return result == .success ? value : nil
    }

    func setAttribute(_ name: String, value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }
}
