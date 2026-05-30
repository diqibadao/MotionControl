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
            t.schedule(deadline: .now() + 0.5, repeating: .milliseconds(500))
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

    // MARK: - 扫描

    private func scan() {
        var newElements: [UIElementInfo] = []

        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            guard let windowsRef = getAttributeValue(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else {
                continue
            }

            for window in windowsRef {
                let axElements = collectInteractiveAXElements(from: window)
                for axElem in axElements {
                    let role = getAttributeValue(axElem, kAXRoleAttribute as String) as? String ?? ""
                    let title = getAttributeValue(axElem, kAXTitleAttribute as String) as? String ?? ""

                    var frame = CGRect.zero
                    if let posVal = getAttributeValue(axElem, kAXPositionAttribute as String),
                       AXValueGetType(posVal) == .cgPoint {
                        var point = CGPoint.zero
                        AXValueGetValue(posVal, .cgPoint, &point)
                        frame.origin = point
                    }
                    if let sizeVal = getAttributeValue(axElem, kAXSizeAttribute as String),
                       AXValueGetType(sizeVal) == .cgSize {
                        var size = CGSize.zero
                        AXValueGetValue(sizeVal, .cgSize, &size)
                        frame.size = size
                    }

                    let isEnabled: Bool
                    if let enabledVal = getAttributeValue(axElem, kAXEnabledAttribute as String),
                       CFGetTypeID(enabledVal) == CFBooleanGetTypeID() {
                        isEnabled = CFBooleanGetValue(enabledVal) != 0
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

        DispatchQueue.main.async {
            self.elements = newElements
        }
    }

    private func collectInteractiveAXElements(from element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []

        // 检查自身是否为交互元素
        if let role = getAttributeValue(element, kAXRoleAttribute as String) as? String,
           Self.isInteractive(role: role) {
            result.append(element)
        }

        // 递归处理子元素
        if let children = getAttributeValue(element, kAXChildrenAttribute as String) as? [AXUIElement] {
            for child in children {
                result.append(contentsOf: collectInteractiveAXElements(from: child))
            }
        }

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

    public static func isInteractive(role: String) -> Bool {
        let interactiveRoles: Set<String> = [
            (kAXButtonRole as String),
            (kAXTextFieldRole as String),
            (kAXCheckBoxRole as String),
            (kAXRadioButtonRole as String),
            (kAXComboBoxRole as String),
            (kAXSliderRole as String),
            (kAXPopUpButtonRole as String),
            (kAXDisclosureTriangleRole as String)
        ]
        return interactiveRoles.contains(role)
    }
}
