// Sources/MotionControl/Control/UIElementScanner.swift
// 沙盒兼容版：AXUIElementCopyElementAtPosition（光标点查）+ 前台 App 一层扫描
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

        // 用 AXUIElementCopyElementAtPosition 点查光标位置
        if let el = elementAt(position: cursor), isInteractive(role: el.role) {
            nearElement = el
        } else {
            // fallback：从缓存匹配
            if let near = nearElement, near.frame.contains(cursor) { return }
            for el in cachedElements {
                if el.frame.contains(cursor) {
                    nearElement = el; return
                }
            }
            nearElement = nil
        }

        // 首次启动后立即触发一次扫描
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
                for el in visible {
                    EventLogger.log(event: "axEl", frame: nil,
                        input: "pid=\(el.owningPID) role=\(el.role)", output: "title=\(el.title) frame=(\(Int(el.frame.origin.x)),\(Int(el.frame.origin.y)),\(Int(el.frame.width)),\(Int(el.frame.height)))", duration: 0)
                }
                if !visible.isEmpty {
                    self.lastScanSuccess = CFAbsoluteTimeGetCurrent()
                    self.cachedElements = visible
                } else if CFAbsoluteTimeGetCurrent() - self.lastScanSuccess > 10.0 {
                    self.cachedElements = []
                }
            }
        }
    }

    // MARK: - AXUIElementCopyElementAtPosition（沙盒兼容）

    /// 查询指定屏幕坐标处的 UI 元素（系统级 API，沙盒 + AX 权限下可用）
    public func elementAt(position: CGPoint) -> UIElementInfo? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(position.x), Float(position.y), &element)
        guard err == .success, let elem = element else { return nil }
        return extractInfo(from: elem)
    }

    // MARK: - 一层扫描（只读前台 App + Dock + SystemUIServer 的窗口直接子元素）

    private let interactiveRoles = Set([
        "AXButton", "AXRadioButton", "AXPopUpButton", "AXCheckBox",
        "AXMenuButton", "AXComboBox", "AXTextField", "AXTextArea",
        "AXSlider", "AXTab", "AXDisclosureTriangle", "AXLink",
        "AXMenuItem", "AXMenuBarItem", "AXDockItem", "AXImage",
        "AXRow", "AXCell", "AXScrollBar",
    ])

    private func isInteractive(role: String) -> Bool {
        interactiveRoles.contains(role)
    }

    private func scanElements(windows: [WindowInfo]) -> [UIElementInfo] {
        var collected: [UIElementInfo] = []

        // 扫描所有可见窗口所属 App（一层：窗口 → 子元素，不递归）
        var scannedPIDs = Set<pid_t>()
        for w in windows {
            let pid = pid_t(w.pid)
            guard pid > 0, !scannedPIDs.contains(pid) else { continue }
            scannedPIDs.insert(pid)
            scanAppOneLevel(pid: pid, into: &collected)
            if collected.count >= 200 { break }
        }

        // Dock
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            scanAppOneLevel(pid: dock.processIdentifier, into: &collected)
        }

        // SystemUIServer（菜单栏）
        if let sysui = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first {
            scanAppOneLevel(pid: sysui.processIdentifier, into: &collected)
        }

        return collected
    }

    /// 只扫描一层：App → 窗口 → 窗口的直接子元素（不递归孙子节点）
    private func scanAppOneLevel(pid: pid_t, into collected: inout [UIElementInfo]) {
        let appEl = AXUIElementCreateApplication(pid)

        guard let windowsRef = getAXAttr(appEl, kAXWindowsAttribute as String) else { return }
        guard CFGetTypeID(windowsRef) == CFArrayGetTypeID() else { return }
        let windowArr = windowsRef as! CFArray
        let windowCount = CFArrayGetCount(windowArr)

        for wi in 0..<min(windowCount, 50) {
            guard collected.count < 200 else { break }
            let winEl = unsafeBitCast(CFArrayGetValueAtIndex(windowArr, wi), to: AXUIElement.self)

            guard let childrenRef = getAXAttr(winEl, kAXChildrenAttribute as String) else { continue }
            guard CFGetTypeID(childrenRef) == CFArrayGetTypeID() else { continue }
            let childArr = childrenRef as! CFArray
            let childCount = CFArrayGetCount(childArr)

            for ci in 0..<min(childCount, 500) {
                guard collected.count < 200 else { break }
                let childEl = unsafeBitCast(CFArrayGetValueAtIndex(childArr, ci), to: AXUIElement.self)
                if let info = extractInfo(from: childEl, pid: Int(pid)), isInteractive(role: info.role) {
                    collected.append(info)
                }
            }
        }
    }

    // MARK: - 提取 UIElementInfo

    private func extractInfo(from element: AXUIElement, pid: Int? = nil) -> UIElementInfo? {
        guard let role = getAXAttr(element, kAXRoleAttribute as String) as? String else { return nil }

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
        guard frame.width > 0, frame.height > 0, area < 50000 else { return nil }

        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        guard frame.intersects(screenFrame) else { return nil }

        let title = (getAXAttr(element, kAXTitleAttribute as String) as? String) ?? ""
        let owningPID: Int
        if let p = pid {
            owningPID = p
        } else {
            var elPid: pid_t = 0; AXUIElementGetPid(element, &elPid); owningPID = Int(elPid)
        }

        return UIElementInfo(role: role, title: title, frame: frame,
            isEnabled: true, subrole: nil, owningPID: owningPID)
    }

    private func getAXAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
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

            guard let myIdx = windows.firstIndex(where: { $0.pid == el.owningPID }) else {
                return true
            }
            guard windows[myIdx].bounds.contains(center) else { return false }

            for i in 0..<myIdx {
                if windows[i].bounds.contains(center) { return false }
            }
            return true
        }
    }
}
