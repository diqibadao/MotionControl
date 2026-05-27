import Foundation

/// 语音输入管理器：监听嘴部事件，控制语音识别启停。
class VoiceInputManager: VoiceRecognizerDelegate {
    private let recognizer = VoiceRecognizer()
    private let textInjector = TextInjector()
    private var isListening = false
    private var mouthOpenSince: Date?
    private let openDurationThreshold: TimeInterval = 0.2

    init() {
        recognizer.delegate = self
    }

    /// 处理嘴部事件
    func handleMouthEvent(_ event: MouthEvent) {
        if event.justOpened {
            mouthOpenSince = Date()
        } else if event.status == .open {
            // 持续张开超过阈值后启动语音
            guard let start = mouthOpenSince else { return }
            if Date().timeIntervalSince(start) > openDurationThreshold && !isListening {
                startListening()
            }
        } else if event.justClosed {
            if isListening {
                stopListening()
            }
            mouthOpenSince = nil
        }
    }

    private func startListening() {
        do {
            try recognizer.start()
            isListening = true
        } catch {
            print("语音启动失败: \(error)")
        }
    }

    private func stopListening() {
        recognizer.stop()
        isListening = false
    }

    // MARK: - VoiceRecognizerDelegate
    func didReceiveText(_ text: String) {
        // 将识别的文本注入
        textInjector.injectText(text)
    }

    func didDetectVoice(_ isSpeaking: Bool) {
        // 可扩展
    }

    func didEncounterError(_ error: Error) {
        print("语音识别错误: \(error)")
    }
}
