import Foundation
import AppKit
import AVFoundation
import Speech

class PermissionManager {
    static let shared = PermissionManager()
    
    func checkAll() async -> (camera: Bool, mic: Bool, speech: Bool, accessibility: Bool) {
        async let camera = checkCamera()
        async let mic = checkMicrophone()
        // Speech 权限检查仅在 App Bundle 环境下执行（CLI 调用 SFSpeechRecognizer API 会 TCC SIGABRT）
        let speech = checkSpeechSafe()
        let accessibility = checkAccessibility()
        return await (camera, mic, speech, accessibility)
    }

    /// 安全版 Speech 权限检查：非 Bundle 环境直接返回 false，避免 TCC 崩溃
    private func checkSpeechSafe() -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        let sem = DispatchSemaphore(value: 0)
        var authorized = false
        SFSpeechRecognizer.requestAuthorization { status in
            authorized = (status == .authorized)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 5)
        return authorized
    }
    
    func checkCamera() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
    
    func checkMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
    
    func checkSpeech() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
    
    func checkAccessibility() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func openAccessibilityPreference() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
