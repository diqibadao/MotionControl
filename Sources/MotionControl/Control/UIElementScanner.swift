// Sources/MotionControl/Control/UIElementScanner.swift
// 通过 AXHelper 独立进程扫描（socket 通信）
import AppKit
import Combine
import Foundation

public struct UIElementInfo: Identifiable, Equatable {
    public let id = UUID()
    public let role: String
    public let title: String
    public let frame: CGRect
    public let isEnabled: Bool
    public let subrole: String?

    public static func == (lhs: UIElementInfo, rhs: UIElementInfo) -> Bool {
        return lhs.role == rhs.role && lhs.title == rhs.title && lhs.frame == rhs.frame && lhs.isEnabled == rhs.isEnabled && lhs.subrole == rhs.subrole
    }
}

public class UIElementScanner: ObservableObject {
    @Published public var nearElement: UIElementInfo? = nil
    public private(set) var cachedElements: [UIElementInfo] = []
    private var cursorTimer: DispatchSourceTimer?
    private var lastScanTime: TimeInterval = 0
    private let scanInterval: TimeInterval = 2.0
    private var isScanning = false
    private let socketPath = "/tmp/axhelper.sock"
    /// 锁定的元素：锁住期间 nearElement 不更新，防止 jitter 导致目标跳变
    private var lockedElement: UIElementInfo? = nil

    public init() {}

    /// 锁定一个元素：锁住期间 nearElement 不随光标移动而切换
    public func lockElement(_ el: UIElementInfo) {
        lockedElement = el
        nearElement = el
        EventLogger.log(event: "LOCK", frame: nil, input: "lock", output: "role=\(el.role) title=\(el.title)", duration: nil)
    }

    /// 解锁：恢复正常 nearElement 跟踪
    public func unlockElement() {
        if lockedElement != nil {
            EventLogger.log(event: "LOCK", frame: nil, input: "unlock", output: "resume tracking", duration: nil)
        }
        lockedElement = nil
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.2, repeating: .milliseconds(100), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        t.activate()
        cursorTimer = t
    }

    public func stop() {
        cursorTimer?.cancel(); cursorTimer = nil; cachedElements = []
    }

    private func tick() {
        let cursor = NSEvent.mouseLocation
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let axCursor = CGPoint(x: cursor.x, y: screenSize.height - cursor.y)
        // 锁住期间：无条件保持 nearElement，防 jitter 跳变（解锁由 CursorController 控制）
        if lockedElement != nil { return }
        // Fast path: nearElement 仍在光标下 → 不重新扫描
        if let near = nearElement, near.frame.contains(axCursor) { return }
        let now = ProcessInfo.processInfo.systemUptime
        if cachedElements.isEmpty || now - lastScanTime > scanInterval { triggerScan() }
        for el in cachedElements {
            if el.frame.contains(axCursor) {
                if nearElement?.id != el.id {
                    EventLogger.log(event: "axMatch", frame: nil, input: "cursor=(\(Int(axCursor.x)),\(Int(axCursor.y)))", output: "role=\(el.role) title=\(el.title)", duration: 0)
                }
                nearElement = el; return
            }
        }
        if nearElement != nil {
            EventLogger.log(event: "axMatch", frame: nil, input: "cursor=(\(Int(axCursor.x)),\(Int(axCursor.y)))", output: "lost", duration: 0)
        }
        nearElement = nil
    }

    private func triggerScan() {
        guard !isScanning else { return }
        isScanning = true

        let t0 = CFAbsoluteTimeGetCurrent()
        let elements = socketScan()
        let elapsed = CFAbsoluteTimeGetCurrent() - t0  // 秒，EventLogger 内部 ×1000 显示 ms
        EventLogger.log(event: "axScan", frame: nil, input: "app=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")", output: "elements=\(elements.count)", duration: elapsed)

        if !elements.isEmpty { cachedElements = elements }
        lastScanTime = ProcessInfo.processInfo.systemUptime
        isScanning = false
    }

    private func socketScan() -> [UIElementInfo] {
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { strcpy(&addr.sun_path.0, $0) }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

        // 非阻塞 connect + poll 超时 3 秒
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let addrPtr = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }
        let connResult = connect(sock, addrPtr, addrLen)
        if connResult < 0 && errno == EINPROGRESS {
            var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
            if poll(&pfd, 1, 3000) <= 0 { return [] }
        } else if connResult < 0 {
            return []
        }

        // 恢复阻塞模式
        _ = fcntl(sock, F_SETFL, flags)

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var lenBE: UInt32 = 0
        guard read(sock, &lenBE, 4) == 4 else { return [] }
        let len = Int(UInt32(bigEndian: lenBE))
        guard len > 0, len < 1_000_000 else { return [] }

        var data = Data(); var remaining = len
        var buf = [UInt8](repeating: 0, count: min(remaining, 4096))
        while remaining > 0 {
            let n = read(sock, &buf, min(remaining, buf.count))
            guard n > 0 else { return [] }
            data.append(contentsOf: buf[0..<n]); remaining -= n
        }

        struct H: Codable { let role: String; let frame: [Double]; let title: String }
        guard let list = try? JSONDecoder().decode([H].self, from: data) else { return [] }
        return list.compactMap { el in
            guard el.frame.count == 4 else { return nil }
            return UIElementInfo(role: el.role, title: el.title, frame: CGRect(x: el.frame[0], y: el.frame[1], width: el.frame[2], height: el.frame[3]), isEnabled: true, subrole: nil)
        }
    }
}
