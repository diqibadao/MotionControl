import Foundation
import Speech
import AVFoundation

/// 语音识别委托协议
public protocol VoiceRecognizerDelegate: AnyObject {
    func didReceiveText(_ text: String)
    func didDetectVoice(_ isSpeaking: Bool)
    func didEncounterError(_ error: Error)
}

/// 语音识别器，封装 SFSpeechRecognizer，支持自动重新启动。
public class VoiceRecognizer: NSObject {
    public weak var delegate: VoiceRecognizerDelegate?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.motioncontrol.voice")

    private var isRunning = false
    private var restartTimer: Timer?

    /// 1 分钟自动重启间隔
    private let restartInterval: TimeInterval = 60

    // MARK: - 错误重试上限
    private var retryCount = 0
    private let maxRetryCount = 5
    /// 标记本次启动是否由错误重试触发（不影响重试计数）
    private var isRetry = false

    public override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        super.init()
        speechRecognizer?.delegate = self
    }

    /// 启动语音识别
    public func start() throws {
        // 非重试时重置计数，以便手动启动后重新计数
        if !isRetry {
            retryCount = 0
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NSError(domain: "VoiceRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "语音识别不可用"])
        }

        if isRunning { stop() }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.delegate?.didReceiveText(text)
                // 成功接收到识别结果，重置重试次数
                self.retryCount = 0
            }
            if let error = error {
                self.delegate?.didEncounterError(error)
                self.stop()
                // 未超过上限则安排重试
                if self.retryCount < self.maxRetryCount {
                    self.retryCount += 1
                    self.isRetry = true
                    self.scheduleRestart()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true

        isRetry = false // 清除重试标记，避免影响后续自动重启

        // 1分钟自动重启
        restartTimer = Timer.scheduledTimer(withTimeInterval: restartInterval, repeats: false) { [weak self] _ in
            // 定时重启属于正常重新连接，应清空重试计数
            self?.isRetry = false
            self?.restart()
        }
    }

    /// 停止语音识别
    public func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        restartTimer?.invalidate()
        restartTimer = nil
        isRunning = false
    }

    private func scheduleRestart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restart()
        }
    }

    private func restart() {
        stop()
        do {
            try start()
        } catch {
            delegate?.didEncounterError(error)
        }
    }

    deinit {
        stop()
    }
}

extension VoiceRecognizer: SFSpeechRecognizerDelegate {
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            // 可尝试重启
        }
    }
}
