// Sources/AXHelper/main.swift
// AXHelper — 独立 AX 扫描进程（无沙盒签名），通过 UNIX Socket 接收窗口列表，返回扫描结果
// 由 launchd LaunchAgent 拉起：com.motioncontrol.axhelper
import Foundation
import AppKit
import ApplicationServices

// MARK: - 共享类型（与 UIElementScanner 保持一致，不在 target 间共享代码）

struct ElementDTO: Codable {
    let role: String; let frame: [Double]; let title: String; let pid: Int
}

struct ScanRequest: Codable {
    let windows: [WindowInfo]
    struct WindowInfo: Codable {
        let pid: Int; let bounds: [Double]; let layer: Int
    }
}

// MARK: - AX 扫描逻辑

let interactiveRoles = Set([
    "AXButton", "AXRadioButton", "AXPopUpButton", "AXCheckBox",
    "AXMenuButton", "AXComboBox", "AXTextField", "AXTextArea",
    "AXSlider", "AXTab", "AXDisclosureTriangle", "AXLink",
    "AXMenuItem", "AXMenuBarItem", "AXDockItem", "AXImage",
    "AXRow", "AXCell", "AXScrollBar",
])

func getAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func performAXScan(windows: [ScanRequest.WindowInfo]) -> [ElementDTO] {
    var collected: [ElementDTO] = []

    func scanAppWindow(_ pid: pid_t) {
        guard pid > 0 else { return }
        let appEl = AXUIElementCreateApplication(pid)
        walk(element: appEl, depth: 0, collected: &collected, pid: pid)
    }

    for w in windows { scanAppWindow(pid_t(w.pid)) }

    // Dock
    if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
        scanAppWindow(dock.processIdentifier)
    }
    // SystemUIServer
    if let sysui = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first {
        scanAppWindow(sysui.processIdentifier)
    }
    // 焦点元素
    if let focusDTO = scanFocusedElement() { collected.append(focusDTO) }

    return collected
}

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
    var elPid: pid_t = 0; AXUIElementGetPid(axEl, &elPid)
    let title = (getAttr(axEl, kAXTitleAttribute as String) as? String)
        ?? (getAttr(axEl, kAXValueAttribute as String) as? String) ?? ""
    return ElementDTO(role: role, frame: [frame.origin.x, frame.origin.y, frame.width, frame.height], title: title, pid: Int(elPid))
}

let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

func walk(element: AXUIElement, depth: Int, collected: inout [ElementDTO], maxDepth: Int = 25, pid: pid_t) {
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

    let area = frame.width * frame.height
    if interactiveRoles.contains(role), frame.width > 0, frame.height > 0, area < 50000,
       frame.intersects(screenFrame) {
        let title = (getAttr(element, kAXTitleAttribute as String) as? String) ?? ""
        collected.append(ElementDTO(role: role, frame: [Double(frame.origin.x), Double(frame.origin.y), Double(frame.width), Double(frame.height)], title: title, pid: Int(pid)))
    }

    guard let children = getAttr(element, kAXChildrenAttribute as String) else { return }
    guard CFGetTypeID(children) == CFArrayGetTypeID() else { return }
    let arr = children as! CFArray
    for i in 0..<CFArrayGetCount(arr) {
        walk(element: unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: AXUIElement.self),
             depth: depth + 1, collected: &collected, maxDepth: maxDepth, pid: pid)
    }
}

// MARK: - UNIX Socket Server

let socketPath: String
if let idx = CommandLine.arguments.firstIndex(of: "--socket") {
    socketPath = CommandLine.arguments[idx + 1]
} else {
    socketPath = "/tmp/com.motioncontrol.axhelper.sock"
}

let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { fputs("[AXHelper] socket() failed: \(String(cString: strerror(errno)))\n", stderr); exit(1) }
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
unlink(socketPath)
socketPath.withCString { strcpy(&addr.sun_path.0, $0) }
let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
guard bind(sock, UnsafeRawPointer(&addr).assumingMemoryBound(to: sockaddr.self), addrLen) == 0 else {
    fputs("[AXHelper] bind failed: \(String(cString: strerror(errno)))\n", stderr); exit(1)
}
guard listen(sock, 5) == 0 else { fputs("[AXHelper] listen failed\n", stderr); exit(1) }
fputs("[AXHelper] listening on \(socketPath)\n", stderr)

signal(SIGTERM) { _ in fputs("[AXHelper] exiting\n", stderr); exit(0) }
signal(SIGINT)  { _ in fputs("[AXHelper] exiting\n", stderr); exit(0) }

while true {
    let client = accept(sock, nil, nil)
    guard client >= 0 else { continue }

    var reqLenBE: UInt32 = 0
    guard read(client, &reqLenBE, 4) == 4 else { close(client); continue }
    let reqLen = Int(UInt32(bigEndian: reqLenBE))
    guard reqLen > 0, reqLen < 100_000 else { close(client); continue }

    var reqData = Data(); var reqRemaining = reqLen
    var buf = [UInt8](repeating: 0, count: min(reqRemaining, 4096))
    while reqRemaining > 0 {
        let n = read(client, &buf, min(reqRemaining, buf.count))
        guard n > 0 else { break }
        reqData.append(contentsOf: buf[0..<n]); reqRemaining -= n
    }

    let windows: [ScanRequest.WindowInfo]
    if let req = try? JSONDecoder().decode(ScanRequest.self, from: reqData) { windows = req.windows }
    else { windows = [] }

    let t0 = CFAbsoluteTimeGetCurrent()
    let elements = performAXScan(windows: windows)
    let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    fputs("[AXHelper] scanned \(elements.count) elements from \(windows.count) windows in \(Int(elapsed))ms\n", stderr)

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
