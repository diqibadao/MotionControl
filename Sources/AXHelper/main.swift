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
    "AXLink", "AXMenuButton", "AXComboBox", "AXTextField",
    "AXSlider", "AXTab", "AXScrollBar", "AXMenuItem",
    "AXCell", "AXRow", "AXImage",
])

func getAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func performAXScan() -> [ElementDTO] {
    var collected: [ElementDTO] = []
    guard let frontApp = NSWorkspace.shared.frontmostApplication else { return collected }
    let appEl = AXUIElementCreateApplication(frontApp.processIdentifier)
    walk(element: appEl, depth: 0, collected: &collected)
    return collected
}

func walk(element: AXUIElement, depth: Int, collected: inout [ElementDTO], maxDepth: Int = 20) {
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

    if interactiveRoles.contains(role), frame.width > 0, frame.height > 0 {
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
