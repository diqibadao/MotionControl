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

    private let backendQueue = DispatchQueue(label: "com.motioncontrol.uielementscanner", qos: .utility)
    private var timer: DispatchSourceTimer?

    public init() {}

    public func start() {
        backendQueue.async { [weak self] in
            guard let self = self else { return }
            // P-LOGIC: 立即执行一次轻量扫描
            self.scan()

            let t = DispatchSource.makeTimerSource(queue: self.backendQueue)
            t.schedule(deadline: .now() + 0.5, repeating: .milliseconds(5000), leeway: .milliseconds(1000))
            t.setEventHandler { [weak self] in
                self?.scan()
            }
            t.activate()
            self.timer = t
        }
    }

    public func stop() {
        backendQueue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
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

    // P-LOGIC: 轻量扫描，只检查几个预定义屏幕点，最多保留 100 个元素
    private func scan() {
        let scanStart = CFAbsoluteTimeGetCurrent()
        var newElements: [UIElementInfo] = []
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - scanStart) * 1000
            let input = "scan"
            let output = "elements=\(newElements.count)"
            // 扫描日志使用 nil frameId
            EventLogger.log(event: "scan", frame: nil, input: input, output: output, duration: duration)
        }

        guard let screenFrame = NSScreen.main?.frame else { return }

        let center = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        let topLeft = CGPoint(x: screenFrame.minX + 1, y: screenFrame.maxY - 1)
        let topRight = CGPoint(x: screenFrame.maxX - 1, y: screenFrame.maxY - 1)
        let bottomLeft = CGPoint(x: screenFrame.minX + 1, y: screenFrame.minY + 1)
        let bottomRight = CGPoint(x: screenFrame.maxX - 1, y: screenFrame.minY + 1)
        let points = [center, topLeft, topRight, bottomLeft, bottomRight]

        for pt in points {
            guard newElements.count < 100 else { break }
            if let info = elementAt(position: pt) {
                if !newElements.contains(info) {
                    newElements.append(info)
                }
            }
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
