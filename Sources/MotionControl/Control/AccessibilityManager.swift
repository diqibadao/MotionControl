import Foundation
import ApplicationServices

/// 辅助功能权限管理器
public class AccessibilityManager {
    public static let shared = AccessibilityManager()

    private init() {}

    /// 检查应用是否拥有辅助功能权限
    public var isTrusted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 弹出系统授权窗口
    public func promptUser() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
