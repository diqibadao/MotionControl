import Cocoa
import ApplicationServices

/// App Store 版 AX 扫描器 — 直接在主进程中调用，无需子进程。
/// 提取自 AXHelper/main.swift 的 scan 逻辑。
enum AXScanner {
    static let interactiveRoles = Set([
        "AXButton", "AXRadioButton", "AXPopUpButton", "AXCheckBox",
        "AXMenuButton", "AXComboBox", "AXTextField", "AXTextArea",
        "AXSlider", "AXTab", "AXScrollBar", "AXTabGroup", "AXToolbar",
        "AXMenuItem", "AXMenuBarItem", "AXDockItem", "AXImage",
    ])
    
    struct ScanElement: Codable {
        let role: String; let frame: [Double]; let title: String; let pid: Int
    }
    
    struct WindowInfo {
        let pid: Int; let bounds: [Double]; let layer: Int
    }
    
    static func scan(windows: [WindowInfo]) -> [ScanElement] {
        var collected: [ScanElement] = []
        for w in windows {
            let appEl = AXUIElementCreateApplication(pid_t(w.pid))
            walk(element: appEl, depth: 0, collected: &collected, pid: pid_t(w.pid))
        }
        // Dock
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            let appEl = AXUIElementCreateApplication(dock.processIdentifier)
            walk(element: appEl, depth: 0, collected: &collected, pid: dock.processIdentifier)
        }
        // SystemUIServer
        if let sysui = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first {
            let appEl = AXUIElementCreateApplication(sysui.processIdentifier)
            walk(element: appEl, depth: 0, collected: &collected, pid: sysui.processIdentifier)
        }
        return collected
    }
    
    private static func getAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }
    
    private static let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    
    private static func walk(element: AXUIElement, depth: Int, collected: inout [ScanElement], maxDepth: Int = 25, pid: pid_t) {
        guard depth <= maxDepth else { return }
        guard let role = getAttr(element, kAXRoleAttribute as String) as? String else { return }

        guard interactiveRoles.contains(role) else {
            guard let children = getAttr(element, kAXChildrenAttribute as String) else { return }
            guard CFGetTypeID(children) == CFArrayGetTypeID() else { return }
            let arr = children as! CFArray
            for i in 0..<CFArrayGetCount(arr) {
                walk(element: unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: AXUIElement.self),
                     depth: depth + 1, collected: &collected, maxDepth: maxDepth, pid: pid)
            }
            return
        }

        var frame = CGRect.zero
        if let posVal = getAttr(element, kAXPositionAttribute as String) {
            let axVal = unsafeBitCast(posVal, to: AXValue.self)
            if AXValueGetType(axVal) == .cgPoint { var p = CGPoint.zero; AXValueGetValue(axVal, .cgPoint, &p); frame.origin = p }
        }
        if let sizeVal = getAttr(element, kAXSizeAttribute as String) {
            let axVal = unsafeBitCast(sizeVal, to: AXValue.self)
            if AXValueGetType(axVal) == .cgSize { var s = CGSize.zero; AXValueGetValue(axVal, .cgSize, &s); frame.size = s }
        }

        let area = frame.width * frame.height
        if frame.width > 0, frame.height > 0, area < 50000,
           frame.intersects(screenFrame) {
            let title = (getAttr(element, kAXTitleAttribute as String) as? String) ?? ""
            collected.append(ScanElement(role: role, frame: [Double(frame.origin.x), Double(frame.origin.y), Double(frame.width), Double(frame.height)], title: title, pid: Int(pid)))
        }

        guard let children = getAttr(element, kAXChildrenAttribute as String) else { return }
        guard CFGetTypeID(children) == CFArrayGetTypeID() else { return }
        let arr = children as! CFArray
        for i in 0..<CFArrayGetCount(arr) {
            walk(element: unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: AXUIElement.self),
                 depth: depth + 1, collected: &collected, maxDepth: maxDepth, pid: pid)
        }
    }
}
