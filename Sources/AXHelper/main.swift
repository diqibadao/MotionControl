import Foundation
import AppKit
import ApplicationServices

// AX Helper：LaunchAgent，由 launchd 拉起，通过 XPC 提供 AX 扫描服务
// 独立 task group，无 IPC 限速

// MARK: - 共享类型（与主 APP 保持一致，不能跨 target 引用）

@objc protocol AXHelperProtocol {
    func scan(reply: @escaping (Data) -> Void)
}

struct ElementDTO: Codable {
    let role: String; let frame: [Double]; let title: String
}

// MARK: - AX 扫描逻辑

let interactiveRoles = Set([
    "AXButton", "AXRadioButton", "AXPopUpButton", "AXCheckBox",
    "AXLink", "AXMenuButton", "AXComboBox", "AXTextField", "AXTextArea",
    "AXSlider", "AXTab", "AXScrollBar", "AXMenuItem",
    "AXMenuBarItem", "AXDockItem", "AXCell", "AXRow", "AXImage",
    "AXWebArea", "AXStaticText", "AXHeading",
])

func getAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func performAXScan() -> [ElementDTO] {
    var collected: [ElementDTO] = []

    /// 扫一个进程的完整 AX 树（屏幕外交集过滤在 walk 里做）
    func scanApp(_ pid: pid_t) {
        guard pid > 0 else { return }
        let appEl = AXUIElementCreateApplication(pid)
        walk(element: appEl, depth: 0, collected: &collected)
    }

    /// 找第一个有可见主窗口的 APP（前台可能最小化了）
    func firstAppWithWindow() -> pid_t {
        // 先看前台
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier > 0 {
            let appEl = AXUIElementCreateApplication(front.processIdentifier)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXMainWindowAttribute as CFString, &win) == .success {
                return front.processIdentifier
            }
        }
        // 前台没窗口 → 遍历其他 APP，找第一个有窗口的
        let allApps = NSWorkspace.shared.runningApplications
        for app in allApps {
            if app.processIdentifier <= 0 { continue }
            if app.bundleIdentifier == "com.apple.dock" { continue }
            if app.bundleIdentifier == "com.apple.systemuiserver" { continue }
            if app.bundleIdentifier == Bundle.main.bundleIdentifier { continue }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXMainWindowAttribute as CFString, &win) == .success {
                return app.processIdentifier
            }
        }
        return 0
    }

    // 1. 可见窗口的 APP
    let visibleAppPID = firstAppWithWindow()
    if visibleAppPID > 0 {
        scanApp(visibleAppPID)
    }

    // 2. 底部 Dock
    if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
        scanApp(dock.processIdentifier)
    }

    // 3. 右上角系统图标（菜单栏右侧）
    if let sysui = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first {
        scanApp(sysui.processIdentifier)
    }

    // 4. 焦点元素（键盘焦点所在，覆盖 Web 编辑区等非标准 AX 元素）
    if let focusDTO = scanFocusedElement() {
        collected.append(focusDTO)
    }

    return collected
}

/// 扫描系统当前焦点元素（键盘焦点所在，如输入框、编辑器）
func scanFocusedElement() -> ElementDTO? {
    let sysWide = AXUIElementCreateSystemWide()
    var focusedEl: CFTypeRef?
    guard AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &focusedEl) == .success,
          let el = focusedEl else { return nil }
    let axEl = el as! AXUIElement

    guard let role = getAttr(axEl, kAXRoleAttribute as String) as? String else { return nil }

    var frame = CGRect.zero
    if let posVal = getAttr(axEl, kAXPositionAttribute as String) {
        let axVal = unsafeBitCast(posVal, to: AXValue.self)
        if AXValueGetType(axVal) == .cgPoint { var p = CGPoint.zero; AXValueGetValue(axVal, .cgPoint, &p); frame.origin = p }
    }
    if let sizeVal = getAttr(axEl, kAXSizeAttribute as String) {
        let axVal = unsafeBitCast(sizeVal, to: AXValue.self)
        if AXValueGetType(axVal) == .cgSize { var s = CGSize.zero; AXValueGetValue(axVal, .cgSize, &s); frame.size = s }
    }

    guard frame.width > 0, frame.height > 0 else { return nil }
    let title = (getAttr(axEl, kAXTitleAttribute as String) as? String)
                ?? (getAttr(axEl, kAXValueAttribute as String) as? String)
                ?? ""
    return ElementDTO(role: role, frame: [frame.origin.x, frame.origin.y, frame.width, frame.height], title: title)
}

let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

func walk(element: AXUIElement, depth: Int, collected: inout [ElementDTO], maxDepth: Int = 25) {
    guard depth <= maxDepth else { return }
    guard let role = getAttr(element, kAXRoleAttribute as String) as? String else { return }

    var frame = CGRect.zero
    if let posVal = getAttr(element, kAXPositionAttribute as String) {
        let axVal = unsafeBitCast(posVal, to: AXValue.self)
        if AXValueGetType(axVal) == .cgPoint { var p = CGPoint.zero; AXValueGetValue(axVal, .cgPoint, &p); frame.origin = p }
    }
    if let sizeVal = getAttr(element, kAXSizeAttribute as String) {
        let axVal = unsafeBitCast(sizeVal, to: AXValue.self)
        if AXValueGetType(axVal) == .cgSize { var s = CGSize.zero; AXValueGetValue(axVal, .cgSize, &s); frame.size = s }
    }

    // 大元素过滤：面积 > 50000px² 不收入（如 AXWebArea 800×600），但仍遍历子元素
    let area = frame.width * frame.height
    if interactiveRoles.contains(role), frame.width > 0, frame.height > 0, area < 50000,
       frame.intersects(screenFrame) {  // 只看屏幕可见元素
        let title = (getAttr(element, kAXTitleAttribute as String) as? String) ?? ""
        collected.append(ElementDTO(role: role, frame: [frame.origin.x, frame.origin.y, frame.width, frame.height], title: title))
    }

    guard let children = getAttr(element, kAXChildrenAttribute as String) else { return }
    guard CFGetTypeID(children) == CFArrayGetTypeID() else { return }
    let arr = children as! CFArray
    for i in 0..<CFArrayGetCount(arr) {
        walk(element: unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: AXUIElement.self),
             depth: depth + 1, collected: &collected, maxDepth: maxDepth)
    }
}

// MARK: - XPC Service

class AXHelperDelegate: NSObject, NSXPCListenerDelegate, AXHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AXHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func scan(reply: @escaping (Data) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let elements = performAXScan()
        let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        fputs("[AXHelper] scanned \(elements.count) elements in \(Int(elapsed))ms\n", stderr)
        if let json = try? JSONEncoder().encode(elements) {
            reply(json)
        } else {
            reply(Data())
        }
    }
}

// --pipe 模式（命令行直接调用）
if CommandLine.arguments.contains("--pipe") {
    let t0 = CFAbsoluteTimeGetCurrent()
    let elements = performAXScan()
    let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    fputs("[AXHelper] scanned \(elements.count) elements in \(Int(elapsed))ms\n", stderr)
    if let json = try? JSONEncoder().encode(elements) {
        FileHandle.standardOutput.write(json)
    }
    exit(0)
}

if CommandLine.arguments.contains("--xpc") {
    // LaunchAgent XPC 模式（生产环境）
    let delegate = AXHelperDelegate()
    let listener = NSXPCListener(machServiceName: "com.motioncontrol.axhelper")
    listener.delegate = delegate
    listener.resume()
    fputs("[AXHelper] XPC listener started\n", stderr)
    RunLoop.main.run()
} else {
    // 默认：UNIX Socket 模式（开发/手动启动）
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else { fputs("[AXHelper] socket failed\n", stderr); exit(1) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let socketPath = "/tmp/axhelper.sock"
    unlink(socketPath)
    socketPath.withCString { strcpy(&addr.sun_path.0, $0) }
    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    guard bind(sock, UnsafeRawPointer(&addr).assumingMemoryBound(to: sockaddr.self), addrLen) == 0 else {
        fputs("[AXHelper] bind failed: \(String(cString: strerror(errno)))\n", stderr)
        exit(1)
    }
    guard listen(sock, 5) == 0 else { fputs("[AXHelper] listen failed\n", stderr); exit(1) }
    fputs("[AXHelper] socket listening on \(socketPath)\n", stderr)

    while true {
        let client = accept(sock, nil, nil)
        guard client >= 0 else { continue }
        let t0 = CFAbsoluteTimeGetCurrent()
        let elements = performAXScan()
        let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        fputs("[AXHelper] scanned \(elements.count) elements in \(Int(elapsed))ms\n", stderr)
        if let json = try? JSONEncoder().encode(elements) {
            var len = UInt32(json.count).bigEndian
            _ = json.withUnsafeBytes { ptr in
                write(client, &len, 4)
                write(client, ptr.baseAddress!, json.count)
            }
        } else {
            var zero: UInt32 = 0
            write(client, &zero, 4)
        }
        close(client)
    }
}
