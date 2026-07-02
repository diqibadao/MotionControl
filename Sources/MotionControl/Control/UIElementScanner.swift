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
    private var consecutiveFailures = 0
    private let maxFailures = 3
    private var axHelperProcess: Process?
    private var lastScanSuccess: CFAbsoluteTime = 0

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
        killAXHelper()
    }

    // MARK: - Tick（0.5s 定时，无任何触发条件）

    private func tick() {
        let cursor = NSEvent.mouseLocation
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let axCursor = cursor  // 统一坐标系：cursor 和 el.frame 均为 Quartz，无需翻转

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
                // AXHelper 挂了检测：连续失败 N 次 → 自动重启
                if visible.isEmpty && !windows.isEmpty {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures >= self.maxFailures {
                        EventLogger.log(event: "axHelper", frame: nil, input: "dead, respawning", output: "failures=\(self.consecutiveFailures)", duration: 0)
                        self.spawnAXHelper()
                        self.consecutiveFailures = 0
                    }
                } else {
                    self.consecutiveFailures = 0
                }
                let pidBreakdown = Dictionary(grouping: visible, by: { $0.owningPID }).map { "pid\($0.key)=\($0.value.count)" }.joined(separator: " ")
                EventLogger.log(event: "axScan", frame: nil,
                    input: "windows=\(windows.count)", output: "raw=\(rawElements.count) visible=\(visible.count) [\(pidBreakdown)]", duration: elapsed)
                // 每个可见元素的详细日志：pid|role|title|frame
                for el in visible {
                    EventLogger.log(event: "axEl", frame: nil,
                        input: "pid=\(el.owningPID) role=\(el.role)", output: "title=\(el.title) frame=(\(Int(el.frame.origin.x)),\(Int(el.frame.origin.y)),\(Int(el.frame.width)),\(Int(el.frame.height)))", duration: 0)
                }
                if visible.isEmpty {
                    if CFAbsoluteTimeGetCurrent() - self.lastScanSuccess < 3.0 {
                        // AXHelper 暂时掉线，保留旧缓存避免蒙层闪烁
                    } else {
                        self.cachedElements = []
                    }
                } else {
                    self.lastScanSuccess = CFAbsoluteTimeGetCurrent()
                    self.cachedElements = visible
                }
            }
        }
    }

    // MARK: - AXHelper 生命周期

    /// 启动（或重启）AXHelper 进程。先杀旧进程，再 spawn 新的。
    public func spawnAXHelper() {
        killAXHelper()
        guard let execURL = Bundle.main.executableURL else { return }
        let axHelperURL = execURL.deletingLastPathComponent().appendingPathComponent("AXHelper")
        let task = Process()
        task.executableURL = axHelperURL
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            axHelperProcess = task
            EventLogger.log(event: "axHelper", frame: nil, input: "spawned", output: "pid=\(task.processIdentifier)", duration: 0)
        } catch {
            EventLogger.log(event: "axHelper", frame: nil, input: "spawn failed", output: error.localizedDescription, duration: 0)
        }
    }

    /// 终止 AXHelper 进程并清理 socket
    public func killAXHelper() {
        if let p = axHelperProcess {
            p.terminate()
            axHelperProcess = nil
        }
        unlink(socketPath)
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
        var pidBounds: [Int: CGRect] = [:]  // PID → 所有窗口的并集矩形
        var pidLayer: [Int: Int] = [:]      // PID → 最上层窗口的 layer
        for win in list {
            let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let name = win[kCGWindowOwnerName as String] as? String ?? ""
            let layer = win[kCGWindowLayer as String] as? Int32 ?? 0
            let bounds = win[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]

            guard pid != myPID else { continue }
            guard !skipOwners.contains(name) else { continue }
            let bw = bounds["Width"] ?? 0, bh = bounds["Height"] ?? 0
            guard bw > 0, bh > 0 else { continue }

            let intPID = Int(pid)
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bw, height: bh)
            if let existing = pidBounds[intPID] {
                pidBounds[intPID] = existing.union(rect)  // 并集矩形
            } else {
                pidBounds[intPID] = rect
                pidLayer[intPID] = Int(layer)
            }
        }
        // 按 CGWindowList 原始顺序输出（顶到底），PID 去重，bounds 取并集
        var seenPID = Set<Int>()
        for win in list {
            let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let name = win[kCGWindowOwnerName as String] as? String ?? ""
            guard pid != myPID else { continue }
            guard !skipOwners.contains(name) else { continue }
            let bw = win[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            guard (bw["Width"] ?? 0) > 0, (bw["Height"] ?? 0) > 0 else { continue }

            let intPID = Int(pid)
            guard !seenPID.contains(intPID) else { continue }
            seenPID.insert(intPID)

            let unionBounds = pidBounds[intPID] ?? .zero
            result.append(WindowInfo(pid: intPID, bounds: unionBounds, layer: pidLayer[intPID] ?? 0))
        }
        return result  // CGWindowList 原始顺序 = 从顶到底
    }

    // MARK: - 遮挡过滤

    private func filterVisible(_ elements: [UIElementInfo], windows: [WindowInfo]) -> [UIElementInfo] {
        guard !windows.isEmpty else { return elements }
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

        return elements.filter { el in
            let center = CGPoint(x: el.frame.midX, y: el.frame.midY)

            // 中心点必须在屏幕内，底部留 30px 杀 Finder 隐藏工具栏
            guard center.x > 0 && center.x < screenRect.maxX,
                  center.y > 0 && center.y < screenRect.maxY - 30 else { return false }

            // 用 PID 匹配元素所属窗口
            guard let myIdx = windows.firstIndex(where: { $0.pid == el.owningPID }) else {
                return true  // Dock/系统元素无窗口 → 保留
            }

            // 元素必须在所属窗口范围内（杀滚动溢出的隐藏元素）
            guard windows[myIdx].bounds.contains(center) else { return false }

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

        struct H: Codable { let role: String; let frame: [Double]; let title: String; let pid: Int }
        guard let list = try? JSONDecoder().decode([H].self, from: data) else { return [] }
        return list.compactMap { el in
            guard el.frame.count == 4 else { return nil }
            return UIElementInfo(role: el.role, title: el.title,
                frame: CGRect(x: el.frame[0], y: el.frame[1], width: el.frame[2], height: el.frame[3]),
                isEnabled: true, subrole: nil, owningPID: el.pid)
        }
    }
}
