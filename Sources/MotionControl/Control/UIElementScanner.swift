// Sources/MotionControl/Control/UIElementScanner.swift
// 所见即所得：CGWindowList → 所有屏幕窗口 → 遮挡过滤 → 只标用户看得见的按钮
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
    public let owningPID: Int
    public let windowBounds: CGRect

    public static func == (lhs: UIElementInfo, rhs: UIElementInfo) -> Bool {
        return lhs.role == rhs.role && lhs.title == rhs.title && lhs.frame == rhs.frame && lhs.isEnabled == rhs.isEnabled && lhs.subrole == rhs.subrole && lhs.owningPID == rhs.owningPID
    }
}

public class UIElementScanner: ObservableObject {
    @Published public var nearElement: UIElementInfo? = nil
    public private(set) var cachedElements: [UIElementInfo] = []
    private var cursorTimer: DispatchSourceTimer?
    private var isScanning = false
    private let socketPath = "/tmp/axhelper.sock"

    public init() {}

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500), leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        t.activate()
        cursorTimer = t
    }

    public func stop() {
        cursorTimer?.cancel(); cursorTimer = nil; cachedElements = []
    }

    // MARK: - Tick（0.5s 定时，无任何触发条件）

    private func tick() {
        let cursor = NSEvent.mouseLocation
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let axCursor = CGPoint(x: cursor.x, y: screenSize.height - cursor.y)

        triggerScan()

        // nearElement 匹配
        if let near = nearElement, near.frame.contains(axCursor) { return }
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

    // MARK: - 扫描

    private func triggerScan() {
        guard !isScanning else { return }
        isScanning = true

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()

            // 1. 拿屏幕上所有可见窗口
            let windows = self.visibleWindows()
            // 2. 构建请求 → 发 AXHelper → 收结果
            let rawElements = self.socketScan(windows: windows)
            // 3. 遮挡过滤
            let visible = self.filterVisible(rawElements, windows: windows)
            let elapsed = CFAbsoluteTimeGetCurrent() - t0

            DispatchQueue.main.async {
                self.isScanning = false
                let pidBreakdown = Dictionary(grouping: visible, by: { $0.owningPID }).map { "pid\($0.key)=\($0.value.count)" }.joined(separator: " ")
                EventLogger.log(event: "axScan", frame: nil,
                    input: "windows=\(windows.count)", output: "raw=\(rawElements.count) visible=\(visible.count) [\(pidBreakdown)]", duration: elapsed)
                self.cachedElements = visible
            }
        }
    }

    // MARK: - 窗口列表

    private struct WindowInfo {
        let pid: Int; let bounds: CGRect; let layer: Int
    }

    private func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let skipOwners = Set(["MotionControl", "AXHelper", "Window Server", "墙纸", "程序坞"])

        var result: [WindowInfo] = []
        var seenPID = Set<Int>()
        for win in list {
            let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let name = win[kCGWindowOwnerName as String] as? String ?? ""
            let layer = win[kCGWindowLayer as String] as? Int32 ?? 0
            let bounds = win[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]

            guard pid != myPID else { continue }
            guard !skipOwners.contains(name) else { continue }
            let bw = bounds["Width"] ?? 0, bh = bounds["Height"] ?? 0
            guard bw > 0, bh > 0 else { continue }

            // PID 去重：同一进程只在最上层窗口扫一次
            let intPID = Int(pid)
            guard !seenPID.contains(intPID) else { continue }
            seenPID.insert(intPID)

            result.append(WindowInfo(pid: intPID, bounds: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bw, height: bh), layer: Int(layer)))
        }
        return result  // CGWindowList 原始顺序 = 从顶到底
    }

    // MARK: - 遮挡过滤

    private func filterVisible(_ elements: [UIElementInfo], windows: [WindowInfo]) -> [UIElementInfo] {
        guard !windows.isEmpty else { return elements }

        return elements.filter { el in
            let center = CGPoint(x: el.frame.midX, y: el.frame.midY)

            // 元素必须在自己窗口范围内（杀悬浮元素、菜单栏项、tooltip）
            guard el.windowBounds.contains(center) else { return false }

            // 用 PID 匹配元素所属窗口
            guard let myIdx = windows.firstIndex(where: { $0.pid == el.owningPID }) else {
                return true  // Dock/焦点元素无窗口 → 保留
            }

            // 检查更高层窗口是否盖住了中心点
            for i in 0..<myIdx {
                let upper = windows[i]
                if upper.bounds.contains(center) { return false }
            }
            return true
        }
    }

    // MARK: - Socket 通信

    private func socketScan(windows: [WindowInfo]) -> [UIElementInfo] {
        let request: [String: Any] = [
            "windows": windows.map { [
                "pid": $0.pid,
                "bounds": [Double($0.bounds.origin.x), Double($0.bounds.origin.y), Double($0.bounds.width), Double($0.bounds.height)],
                "layer": $0.layer
            ] }
        ]
        guard let reqJSON = try? JSONSerialization.data(withJSONObject: request) else { return [] }

        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { strcpy(&addr.sun_path.0, $0) }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

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

        _ = fcntl(sock, F_SETFL, flags)

        // 发送请求
        var lenBE = UInt32(reqJSON.count).bigEndian
        _ = reqJSON.withUnsafeBytes { ptr in
            write(sock, &lenBE, 4)
            write(sock, ptr.baseAddress!, reqJSON.count)
        }

        // 读取响应
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var respLenBE: UInt32 = 0
        guard read(sock, &respLenBE, 4) == 4 else { return [] }
        let respLen = Int(UInt32(bigEndian: respLenBE))
        guard respLen > 0, respLen < 10_000_000 else { return [] }

        var data = Data(); var remaining = respLen
        var buf = [UInt8](repeating: 0, count: min(remaining, 4096))
        while remaining > 0 {
            let n = read(sock, &buf, min(remaining, buf.count))
            guard n > 0 else { return [] }
            data.append(contentsOf: buf[0..<n]); remaining -= n
        }

        struct H: Codable { let role: String; let frame: [Double]; let title: String; let pid: Int; let windowBounds: [Double] }
        guard let list = try? JSONDecoder().decode([H].self, from: data) else { return [] }
        return list.compactMap { el in
            guard el.frame.count == 4, el.windowBounds.count == 4 else { return nil }
            return UIElementInfo(role: el.role, title: el.title,
                frame: CGRect(x: el.frame[0], y: el.frame[1], width: el.frame[2], height: el.frame[3]),
                isEnabled: true, subrole: nil, owningPID: el.pid,
                windowBounds: CGRect(x: el.windowBounds[0], y: el.windowBounds[1], width: el.windowBounds[2], height: el.windowBounds[3]))
        }
    }
}
