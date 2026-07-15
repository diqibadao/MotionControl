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
    private var consecutiveFailures = 0
    private let maxFailures = 3
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

            let windows = self.visibleWindows()
            let rawElements = self.directScan(windows: windows)
            let visible = self.filterVisible(rawElements, windows: windows)
            let elapsed = CFAbsoluteTimeGetCurrent() - t0

            DispatchQueue.main.async {
                self.isScanning = false
                if visible.isEmpty && !windows.isEmpty {
                    self.consecutiveFailures += 1
                } else {
                    self.consecutiveFailures = 0
                }
                let pidBreakdown = Dictionary(grouping: visible, by: { $0.owningPID }).map { "pid\($0.key)=\($0.value.count)" }.joined(separator: " ")
                EventLogger.log(event: "axScan", frame: nil,
                    input: "windows=\(windows.count)", output: "raw=\(rawElements.count) visible=\(visible.count) [\(pidBreakdown)]", duration: elapsed)
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

    // MARK: - 直接 AX 扫描（主 App 有 AX 权限，无需子进程）

    private let interactiveRoles = Set([
        "AXButton", "AXRadioButton", "AXPopUpButton", "AXCheckBox",
        "AXMenuButton", "AXComboBox", "AXTextField", "AXTextArea",
        "AXSlider", "AXTab",
        "AXMenuItem", "AXMenuBarItem", "AXDockItem", "AXImage",
    ])

    private func directScan(windows: [WindowInfo]) -> [UIElementInfo] {
        var collected: [UIElementInfo] = []

        func walk(element: AXUIElement, depth: Int, pid: pid_t) {
            guard depth <= 25 else { return }
            var roleCF: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleCF) == .success,
                  let role = roleCF as? String else { return }

            var frame = CGRect.zero
            if let posVal = getAXAttr(element, kAXPositionAttribute as String) {
                let axVal = unsafeBitCast(posVal, to: AXValue.self)
                if AXValueGetType(axVal) == .cgPoint { var p = CGPoint.zero; AXValueGetValue(axVal, .cgPoint, &p); frame.origin = p }
            }
            if let sizeVal = getAXAttr(element, kAXSizeAttribute as String) {
                let axVal = unsafeBitCast(sizeVal, to: AXValue.self)
                if AXValueGetType(axVal) == .cgSize { var s = CGSize.zero; AXValueGetValue(axVal, .cgSize, &s); frame.size = s }
            }

            let area = frame.width * frame.height
            let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            if interactiveRoles.contains(role), frame.width > 0, frame.height > 0, area < 50000, frame.intersects(screenFrame) {
                let title = (getAXAttr(element, kAXTitleAttribute as String) as? String) ?? ""
                collected.append(UIElementInfo(role: role, title: title, frame: frame,
                    isEnabled: true, subrole: nil, owningPID: Int(pid)))
            }

            guard let children = getAXAttr(element, kAXChildrenAttribute as String) else { return }
            guard CFGetTypeID(children) == CFArrayGetTypeID() else { return }
            let arr = children as! CFArray
            for i in 0..<CFArrayGetCount(arr) {
                walk(element: unsafeBitCast(CFArrayGetValueAtIndex(arr, i), to: AXUIElement.self), depth: depth + 1, pid: pid)
            }
        }

        func scanApp(pid: pid_t) {
            guard pid > 0 else { return }
            walk(element: AXUIElementCreateApplication(pid), depth: 0, pid: pid)
        }

        for w in windows {
            scanApp(pid: pid_t(w.pid))
        }
        // Dock
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            scanApp(pid: dock.processIdentifier)
        }
        // SystemUIServer
        if let sysui = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first {
            scanApp(pid: sysui.processIdentifier)
        }

        // 焦点元素
        let sysWide = AXUIElementCreateSystemWide()
        var focusedEl: CFTypeRef?
        if AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &focusedEl) == .success,
           let el = focusedEl {
            let axEl = el as! AXUIElement
            var roleCF: CFTypeRef?
            if AXUIElementCopyAttributeValue(axEl, kAXRoleAttribute as CFString, &roleCF) == .success,
               let role = roleCF as? String {
                var frame = CGRect.zero
                if let pv = getAXAttr(axEl, kAXPositionAttribute as String) {
                    let av = unsafeBitCast(pv, to: AXValue.self)
                    if AXValueGetType(av) == .cgPoint { var p = CGPoint.zero; AXValueGetValue(av, .cgPoint, &p); frame.origin = p }
                }
                if let sv = getAXAttr(axEl, kAXSizeAttribute as String) {
                    let av = unsafeBitCast(sv, to: AXValue.self)
                    if AXValueGetType(av) == .cgSize { var s = CGSize.zero; AXValueGetValue(av, .cgSize, &s); frame.size = s }
                }
                if frame.width > 0, frame.height > 0 {
                    var elPid: pid_t = 0; AXUIElementGetPid(axEl, &elPid)
                    let title = (getAXAttr(axEl, kAXTitleAttribute as String) as? String)
                        ?? (getAXAttr(axEl, kAXValueAttribute as String) as? String) ?? ""
                    let info = UIElementInfo(role: role, title: title, frame: frame,
                        isEnabled: true, subrole: nil, owningPID: Int(elPid))
                    collected.append(info)
                }
            }
        }

        return collected
    }

    private func getAXAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
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

}