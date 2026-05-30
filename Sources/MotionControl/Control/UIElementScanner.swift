import AppKit
import ApplicationServices
import Combine

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
            // 立即执行一次扫描
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

    // MARK: - 扫描
    private func scan() {
        let start = CFAbsoluteTimeGetCurrent()
        let startTime = CFAbsoluteTimeGetCurrent()
        var newElements: [UIElementInfo] = []
        print("[SCANNER] scanning...")
        
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        print("[SCANNER] apps count: \(apps.count)")
        
        for app in apps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            
            guard let windowsRef = getAttributeValue(appElement, kAXWindowsAttribute as String) else {
                continue
            }
            let windowElements = axElements(from: windowsRef)
            print("[SCANNER] app \(app.localizedName ?? "?"): \(windowElements.count) windows")
            
            for window in windowElements {
                let axElements = collectInteractiveAXElements(from: window)
                for axElem in axElements {
                    let role = getAttributeValue(axElem, kAXRoleAttribute as String) as? String ?? ""
                    let title = getAttributeValue(axElem, kAXTitleAttribute as String) as? String ?? ""

                    var frame = CGRect.zero
                    if let posVal = getAttributeValue(axElem, kAXPositionAttribute as String) {
                        let axPos: AXValue = unsafeBitCast(posVal, to: AXValue.self)
                        if AXValueGetType(axPos) == .cgPoint {
                            var point = CGPoint.zero
                            AXValueGetValue(axPos, .cgPoint, &point)
                            frame.origin = point
                        }
                    }
                    if let sizeVal = getAttributeValue(axElem, kAXSizeAttribute as String) {
                        let axSize: AXValue = unsafeBitCast(sizeVal, to: AXValue.self)
                        if AXValueGetType(axSize) == .cgSize {
                            var size = CGSize.zero
                            AXValueGetValue(axSize, .cgSize, &size)
                            frame.size = size
                        }
                    }

                    let isEnabled: Bool
                    if let enabledVal = getAttributeValue(axElem, kAXEnabledAttribute as String),
                       CFGetTypeID(enabledVal) == CFBooleanGetTypeID() {
                        isEnabled = CFBooleanGetValue(enabledVal as! CFBoolean) == true
                    } else {
                        isEnabled = true
                    }

                    let subrole: String?
                    if let subroleVal = getAttributeValue(axElem, kAXSubroleAttribute as String) as? String {
                        subrole = subroleVal
                    } else {
                        subrole = nil
                    }

                    let info = UIElementInfo(role: role,
                                             title: title,
                                             frame: frame,
                                             isEnabled: isEnabled,
                                             subrole: subrole)
                    newElements.append(info)
                }
            }
        }
        
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        
        // 统计元素类型分布
        var roleCounts: [String: Int] = [:]
        for el in newElements {
            roleCounts[el.role, default: 0] += 1
        }
        let typeSummary = roleCounts.sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[SCANNER] found \(newElements.count) interactive elements (\(elapsed)ms) [\(typeSummary)]")
        DispatchQueue.main.async {
            self.elements = newElements
        }

        // EventLogger
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let input = "apps=\(apps.count)"
        let output = "elements=\(newElements.count) [\(typeSummary)]"
        EventLogger.log(event: "scan", frame: nil, input: input, output: output, duration: duration)
    }

    private func collectInteractiveAXElements(from element: AXUIElement) -> [AXUIElement] {
        let start = CFAbsoluteTimeGetCurrent()
        let role = getAttributeValue(element, kAXRoleAttribute as String) as? String ?? "?"
        let hasChildren = getAttributeValue(element, kAXChildrenAttribute as String) != nil

        var result: [AXUIElement] = []

        // 检查自身是否支持 AXPress 操作（比角色白名单更可靠）
        if Self.isInteractive(element) {
            result.append(element)
        }

        // 递归处理子元素
        if let childrenRef = getAttributeValue(element, kAXChildrenAttribute as String) {
            let children = axElements(from: childrenRef)
            for child in children {
                result.append(contentsOf: collectInteractiveAXElements(from: child))
            }
        }

        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let input = "role=\(role) hasChildren=\(hasChildren)"
        let output = "count=\(result.count)"
        EventLogger.log(event: "collectInteractiveAXElements", frame: nil, input: input, output: output, duration: duration)

        return result
    }

    // MARK: - 辅助

    private func getAttributeValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if err == .success {
            return value
        }
        return nil
    }

    /// 检查 AXUIElement 是否可交互（双保险：AXPress + 角色白名单）
    static func isInteractive(_ element: AXUIElement) -> Bool {
        // 获取 role 作为日志输入（无论后续是否使用）
        var roleForInput: String = "?"
        do {
            var roleRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            if err == .success {
                roleForInput = (roleRef as? String) ?? "?"
            }
        }

        let start = CFAbsoluteTimeGetCurrent()

        // ① 查 AXPress 操作（最精准）
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success,
           let actions = actionNames as? [String],
           actions.contains("AXPress") {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            EventLogger.log(event: "isInteractive", frame: nil, input: "role=\(roleForInput)", output: "true(AXPress)", duration: duration)
            return true
        }
        
        // ② 备用：常见交互角色（SwiftUI .onTapGesture 等不暴露 AXPress）
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            EventLogger.log(event: "isInteractive", frame: nil, input: "role=\(roleForInput)", output: "false(noRole)", duration: duration)
            return false
        }
        let interactiveRoles: Set<String> = [
            "AXButton", "AXTextField", "AXCheckBox", "AXRadioButton",
            "AXComboBox", "AXSlider", "AXPopUpButton", "AXDisclosureTriangle",
            "AXLink", "AXImage", "AXRow", "AXCell",
            "AXMenuBarItem", "AXMenuItem", "AXToolbarButton",
            "AXTab", "AXScrollBar", "AXOutline", "AXBrowser", "AXColorWell",
        ]
        let result = interactiveRoles.contains(role)
        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let output = result ? "true(roleList)" : "false(roleList)"
        EventLogger.log(event: "isInteractive", frame: nil, input: "role=\(roleForInput)", output: output, duration: duration)
        return result
    }
}
