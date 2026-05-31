// Sources/MotionControl/Control/UIElementScanner.swift
import AppKit
import ApplicationServices
import Combine

// P-ARCH: UIElementInfo 结构体未更改 (read-only)
public struct UIElementInfo: Identifiable, Equatable {
    public let id = UUID()
    public let role: String
    public let title: String
    public let frame: CGRect
    public let isEnabled: Bool
    public let subrole: String?

    public static func == (lhs: UIElementInfo, rhs: UIElementInfo) -> Bool {
        return lhs.role == rhs.role &&
            lhs.title == rhs.title &&
            lhs.frame == rhs.frame &&
            lhs.isEnabled == rhs.isEnabled &&
            lhs.subrole == rhs.subrole
    }
}

public class UIElementScanner: ObservableObject {
    @Published public var elements: [UIElementInfo] = []
    
    /// 缓存：光标附近的元素（由后台队列更新，主线程读取）
    @Published var nearElement: UIElementInfo? = nil

    private let backendQueue = DispatchQueue(label: "com.motioncontrol.uielementscanner", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var cursorTimer: DispatchSourceTimer?

    public init() {}

    public func start() {
        backendQueue.async { [weak self] in
            guard let self = self else { return }
            self.scan()
            
            // 定时 1：每 5 秒扫前窗元素（远距磁吸缓存）
            let t = DispatchSource.makeTimerSource(queue: self.backendQueue)
            t.schedule(deadline: .now() + 0.5, repeating: .milliseconds(5000), leeway: .milliseconds(1000))
            t.setEventHandler { [weak self] in
                self?.scan()
            }
            t.activate()
            self.timer = t
            
            // 定时 2：每 200ms 刷新光标附近元素（后台调 elementAt，不阻塞主线程）
            let cursorTimer = DispatchSource.makeTimerSource(queue: self.backendQueue)
            cursorTimer.schedule(deadline: .now() + 0.2, repeating: .milliseconds(200), leeway: .milliseconds(50))
            cursorTimer.setEventHandler { [weak self] in
                self?.refreshNearCursor()
            }
            cursorTimer.activate()
            self.cursorTimer = cursorTimer
        }
    }

    public func stop() {
        backendQueue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.cursorTimer?.cancel()
            self?.cursorTimer = nil
        }
    }

    // MARK: - 公开查询接口

    // P-PARAM: 新增 frameId 参数用于日志串联，默认为 nil
    /// 获取指定屏幕坐标处的 UI 元素信息。
    public func elementAt(position: CGPoint, frameId: Int? = nil) -> UIElementInfo? {
        let start = CFAbsoluteTimeGetCurrent()
        var result: UIElementInfo?
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let input = "x=\(Int(position.x)) y=\(Int(position.y))"
            var output: String
            if let info = result {
                output = "role=\(info.role) title=\(info.title)"
            } else {
                output = "nil"
            }
            EventLogger.log(event: "elementAt", frame: frameId, input: input, output: output, duration: duration)
        }

        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(position.x), Float(position.y), &element)
        guard err == .success, let elem = element else { return nil }

        result = extractElementInfo(elem, frameId: frameId)
        return result
    }

    // MARK: - 私有辅助

    /// 后台刷新光标附近元素（每 200ms 由 cursorTimer 调用）
    private func refreshNearCursor() {
        let cursor = NSEvent.mouseLocation
        // 只查光标位置 1 个点
        if let el = elementAt(position: cursor) {
            let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
            let dx = center.x - cursor.x
            let dy = center.y - cursor.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 120 {
                DispatchQueue.main.async { [weak self] in
                    self?.nearElement = el
                }
                return
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.nearElement = nil
        }
    }

    /// 将 CFArray 转换为 [AXUIElement]
    private func axElements(from cfArray: CFTypeRef) -> [AXUIElement] {
        guard CFGetTypeID(cfArray) == CFArrayGetTypeID() else { return [] }
        let count = CFArrayGetCount(cfArray as! CFArray)
        var result: [AXUIElement] = []
        for i in 0..<count {
            let ptr = CFArrayGetValueAtIndex(cfArray as! CFArray, i)
            let element = unsafeBitCast(ptr, to: AXUIElement.self)
            result.append(element)
        }
        return result
    }

    /// 扫描最前面 App 的窗口子元素
    private func scan() {
        let scanStart = CFAbsoluteTimeGetCurrent()
        var newElements: [UIElementInfo] = []
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - scanStart) * 1000
            let input = "scan"
            let output = "elements=\(newElements.count)"
            EventLogger.log(event: "scan", frame: nil, input: input, output: output, duration: duration)
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.activationPolicy == .regular else { return }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        guard let windowsRef = getAttributeValue(appElement, kAXWindowsAttribute as String) else { return }
        let windowElements = axElements(from: windowsRef)

        let interactiveRoles: Set<String> = [
            "AXButton", "AXTextField", "AXRadioButton", "AXPopUpButton",
            "AXCheckBox", "AXSlider", "AXDisclosureTriangle", "AXLink",
            "AXImage", "AXRow", "AXCell", "AXTab", "AXMenuButton",
            "AXComboBox", "AXScrollBar",
        ]

        for window in windowElements {
            guard let childrenRef = getAttributeValue(window, kAXChildrenAttribute as String) else { continue }
            let children = axElements(from: childrenRef)
            for child in children {
                guard newElements.count < 200 else { break }
                guard let role = getAttributeValue(child, kAXRoleAttribute as String) as? String,
                      interactiveRoles.contains(role) else { continue }
                if let info = extractElementInfo(child) {
                    newElements.append(info)
                }
            }
            if newElements.count >= 200 { break }
        }

        DispatchQueue.main.async {
            self.elements = newElements
        }
    }

    // P-LOGIC: 从 AXUIElement 提取 UIElementInfo，新抽取的私有方法
    private func extractElementInfo(_ element: AXUIElement, frameId: Int? = nil) -> UIElementInfo? {
        let start = CFAbsoluteTimeGetCurrent()
        var infoResult: UIElementInfo?
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let role = getAttributeValue(element, kAXRoleAttribute as String) as? String ?? "?"
            let input = "elementRole=\(role)"
            var output: String
            if let info = infoResult {
                output = "role=\(info.role) title=\(info.title)"
            } else {
                output = "nil"
            }
            EventLogger.log(event: "extractElementInfo", frame: frameId, input: input, output: output, duration: duration)
        }

        guard let role = getAttributeValue(element, kAXRoleAttribute as String) as? String else {
            return nil
        }
        let title = getAttributeValue(element, kAXTitleAttribute as String) as? String ?? ""

        var frame = CGRect.zero
        if let posVal = getAttributeValue(element, kAXPositionAttribute as String) {
            let axPos: AXValue = unsafeBitCast(posVal, to: AXValue.self)
            if AXValueGetType(axPos) == .cgPoint {
                var point = CGPoint.zero
                AXValueGetValue(axPos, .cgPoint, &point)
                frame.origin = point
            }
        }
        if let sizeVal = getAttributeValue(element, kAXSizeAttribute as String) {
            let axSize: AXValue = unsafeBitCast(sizeVal, to: AXValue.self)
            if AXValueGetType(axSize) == .cgSize {
                var size = CGSize.zero
                AXValueGetValue(axSize, .cgSize, &size)
                frame.size = size
            }
        }

        let isEnabled: Bool
        if let enabledVal = getAttributeValue(element, kAXEnabledAttribute as String),
           CFGetTypeID(enabledVal) == CFBooleanGetTypeID() {
            isEnabled = CFBooleanGetValue(enabledVal as! CFBoolean)
        } else {
            isEnabled = true
        }

        let subrole: String?
        if let subroleVal = getAttributeValue(element, kAXSubroleAttribute as String) as? String {
            subrole = subroleVal
        } else {
            subrole = nil
        }

        let info = UIElementInfo(role: role, title: title, frame: frame, isEnabled: isEnabled, subrole: subrole)
        infoResult = info
        return info
    }

    // 保留的辅助方法 (read-only)
    private func getAttributeValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if err == .success {
            return value
        }
        return nil
    }
}
