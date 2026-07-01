import AppKit

/// 极简前台 App 检测器 — 每 3s 打印 bundle ID + 进程名到日志
/// 用途：识别抖音/PPT 等特定 app 的播放状态
final class AppDetector {
    static let shared = AppDetector()
    private var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            let app = NSWorkspace.shared.frontmostApplication
            let bundle = app?.bundleIdentifier ?? "nil"
            let name = app?.localizedName ?? "nil"
            EventLogger.log(event: "APP-DETECT", frame: nil, input: "bundle=\(bundle) name=\(name)", output: "", duration: nil)
        }
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
