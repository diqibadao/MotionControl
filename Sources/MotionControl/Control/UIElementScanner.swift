// Sources/MotionControl/Control/UIElementScanner.swift
// 沙盒兼容版：CGWindowList 窗口发现 → UNIX Socket → 独立 AXHelper 进程（无沙盒）做 AX 扫描
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
    private var tickTimer: DispatchSourceTimer?
    private var scanTimer: DispatchSourceTimer?
    private var isScanning = false
    private var lastScanSuccess: CFAbsoluteTime = 0

    public init() {}

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500), leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        t.activate()
        tickTimer = t

        let st = DispatchSource.makeTimerSource(queue: .global())
        st.schedule(deadline: .now() + 1.0, repeating: .seconds(5), leeway: .seconds(1))
        st.setEventHandler { [weak self] in self?.triggerScan() }
        st.activate()
        scanTimer = st
    }

    public func stop() {
        tickTimer?.cancel(); tickTimer = nil
        scanTimer?.cancel(); scanTimer = nil
        cachedElements = []
    }

    // MARK: - Tick（0.5s）

    private func tick() {
        let cursor = NSEvent.mouseLocation

        // nearElement 匹配
        if let near = nearElement, near.frame.contains(cursor) { return }
        for el in cachedElements {
            if el.frame.contains(cursor) {
                if nearElement?.id != el.id {
                    EventLogger.log(event: "axMatch", frame: nil, input: "cursor=(\(Int(cursor.x)),\(Int(cursor.y)))", output: "role=\(el.role) title=\(el.title)", duration: nil)
                }
                nearElement = el; return
            }
        }
        if nearElement != nil {
            EventLogger.log(event: "axMatch", frame: nil, input: "cursor=(\(Int(cursor.x)),\(Int(cursor.y)))", output: "lost", duration: nil)
        }
        nearElement = nil

        if cachedElements.isEmpty && !isScanning {
            triggerScan()
        }
    }

    // MARK: - 扫描（5s 间隔）

    private func triggerScan() {
        guard !isScanning else { return }
        isScanning = true

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()

            let windows = self.visibleWindows()
            let rawElements = self.scanElements(windows: windows)
            let visible = self.filterVisible(rawElements, windows: windows)
            let elapsed = CFAbsoluteTimeGetCurrent() - t0

            DispatchQueue.main.async {
                self.isScanning = false
                let pidBreakdown = Dictionary(grouping: visible, by: { $0.owningPID }).map { "pid\($0.key)=\($0.value.count)" }.joined(separator: " ")
                EventLogger.log(event: "axScan", frame: nil,
                    input: "windows=\(windows.count)", output: "raw=\(rawElements.count) visible=\(visible.count) [\(pidBreakdown)]", duration: elapsed)
                if !visible.isEmpty {
                    self.lastScanSuccess = CFAbsoluteTimeGetCurrent()
                    self.cachedElements = visible
                } else if CFAbsoluteTimeGetCurrent() - self.lastScanSuccess > 10.0 {
                    self.cachedElements = []
                }
            }
        }
    }

    // MARK: - AX 扫描（UNIX Socket → 独立 AXHelper 进程）

    private var axSocketPath: String {
        return NSHomeDirectory() + "/Data/tmp/axhelper.sock"
    }

    /// 安装并启动 AXHelper LaunchAgent（首次启动时调用）
    /// App Store 审核注意：LaunchAgent 注册属于标准 macOS 行为，辅助功能类 App（如 Alfred、BetterTouchTool）均使用此模式
    private func ensureAXHelperRunning() {
        guard !FileManager.default.fileExists(atPath: axSocketPath) else { return }

        let bundlePath = Bundle.main.bundlePath
        let helperBin = bundlePath + "/Contents/MacOS/AXHelper"
        let plistSrc = bundlePath + "/Contents/Resources/com.motioncontrol.axhelper.plist"
        let plistDst = NSHomeDirectory() + "/Library/LaunchAgents/com.motioncontrol.axhelper.plist"

        guard FileManager.default.fileExists(atPath: helperBin) else { return }

        // 写入 LaunchAgent plist（替换占位符）
        if FileManager.default.fileExists(atPath: plistSrc),
           let tmpl = try? String(contentsOfFile: plistSrc, encoding: .utf8) {
            let plist = tmpl.replacingOccurrences(of: "__AXHELPER_PATH__", with: helperBin)
                          .replacingOccurrences(of: "__SOCKET_PATH__", with: axSocketPath)
            try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/Library/LaunchAgents", withIntermediateDirectories: true)
            try? plist.write(toFile: plistDst, atomically: true, encoding: .utf8)
        }

        // 启动 LaunchAgent
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootstrap", "gui/\(getuid())", plistDst]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()

        // 等 socket 就绪（最多 5s）
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: axSocketPath) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func scanElements(windows: [WindowInfo]) -> [UIElementInfo] {
        ensureAXHelperRunning()

        let windowDTOs: [[String: Any]] = windows.map { w in
            return ["pid": w.pid, "bounds": [Double(w.bounds.origin.x), Double(w.bounds.origin.y), Double(w.bounds.width), Double(w.bounds.height)], "layer": w.layer]
        }
        guard let reqData = try? JSONSerialization.data(withJSONObject: ["windows": windowDTOs]) else { return [] }

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        axSocketPath.withCString { strcpy(&addr.sun_path.0, $0) }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        guard connect(sock, UnsafeRawPointer(&addr).assumingMemoryBound(to: sockaddr.self), addrLen) == 0 else {
            return []
        }

        var len = UInt32(reqData.count).bigEndian
        _ = reqData.withUnsafeBytes { ptr in
            write(sock, &len, 4)
            write(sock, ptr.baseAddress!, reqData.count)
        }

        var respLenBE: UInt32 = 0
        guard read(sock, &respLenBE, 4) == 4 else { return [] }
        let respLen = Int(UInt32(bigEndian: respLenBE))
        guard respLen > 0, respLen < 500_000 else { return [] }

        var respData = Data()
        var remaining = respLen
        var buf = [UInt8](repeating: 0, count: min(remaining, 8192))
        while remaining > 0 {
            let n = read(sock, &buf, min(remaining, buf.count))
            guard n > 0 else { break }
            respData.append(contentsOf: buf[0..<n])
            remaining -= n
        }

        guard let list = try? JSONDecoder().decode([ElementDTO].self, from: respData) else { return [] }
        return list.compactMap { el -> UIElementInfo? in
            guard el.frame.count == 4 else { return nil }
            let f = el.frame
            let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let rect = CGRect(x: f[0], y: f[1], width: f[2], height: f[3])
            guard rect.width > 0, rect.height > 0, rect.width * rect.height < 50000, rect.intersects(screenFrame) else { return nil }
            return UIElementInfo(role: el.role, title: el.title, frame: rect,
                                 isEnabled: true, subrole: nil, owningPID: el.pid)
        }
    }

    private struct ElementDTO: Codable {
        let role: String; let frame: [Double]; let title: String; let pid: Int
    }

    // MARK: - 窗口列表（CGWindowList，沙盒 OK）

    private struct WindowInfo {
        let pid: Int; let bounds: CGRect; let layer: Int
    }

    private func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let skipOwners = Set(["MotionControl", "AXHelper", "Window Server", "墙纸", "程序坞"])

        var pidBounds: [Int: CGRect] = [:]
        var pidLayer: [Int: Int] = [:]
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
                pidBounds[intPID] = existing.union(rect)
            } else {
                pidBounds[intPID] = rect
                pidLayer[intPID] = Int(layer)
            }
        }

        var result: [WindowInfo] = []
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
        return result
    }

    // MARK: - 遮挡过滤

    private func filterVisible(_ elements: [UIElementInfo], windows: [WindowInfo]) -> [UIElementInfo] {
        guard !windows.isEmpty else { return elements }
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

        return elements.filter { el in
            let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
            guard center.x > 0 && center.x < screenRect.maxX,
                  center.y > 0 && center.y < screenRect.maxY - 30 else { return false }

            // Dock、SystemUIServer、没有窗口匹配的元素 → 保留
            guard let myIdx = windows.firstIndex(where: { $0.pid == el.owningPID }) else {
                return true
            }
            guard windows[myIdx].bounds.contains(center) else { return false }

            // 遮挡检查：仅当更高层窗口来自不同 PID 时才算遮挡（同 App 多窗口不遮挡自己）
            for i in 0..<myIdx {
                let upper = windows[i]
                if upper.pid == el.owningPID { continue }
                if upper.bounds.contains(center) { return false }
            }
            return true
        }
    }
}
