import AVFoundation
import Foundation

/// 可用摄像头信息
struct CameraInfo: Identifiable {
    let id: String       // uniqueID
    let name: String     // localizedName
}

class CameraService: NSObject {
    /// 共享实例，供 UI 层切换摄像头
    static weak var shared: CameraService?

    // MARK: - Properties
    private let session = AVCaptureSession()
    var cameraSession: AVCaptureSession { session }
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?

    /// Callback invoked every time a new video frame is captured.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    /// Callback invoked with current FPS and the number of timestamps used.
    var onFPSUpdate: ((Double, Int) -> Void)?
    private var frameTimestamps: [Date] = []

    /// 当前帧的尺寸（像素）
    var currentFrameSize: CGSize? = nil

    /// 当前使用的摄像头 ID
    private(set) var activeCameraID: String = ""

    // MARK: - Public API

    /// 列出所有可用摄像头
    static func availableCameras() -> [CameraInfo] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start() {
        start(withDeviceID: nil)
    }

    /// 使用指定摄像头启动（nil = 自动选择最佳）
    func start(withDeviceID deviceID: String?) {
        if !isConfigured {
            configureSession(deviceID: deviceID)
        }
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    /// 运行时切换摄像头
    func switchCamera(to deviceID: String) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }

            self.session.beginConfiguration()

            // 移除旧输入
            if let oldInput = self.currentInput {
                self.session.removeInput(oldInput)
            }

            // 添加新输入
            guard let device = AVCaptureDevice(uniqueID: deviceID),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                print("CameraService: switch camera failed")
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.currentInput = input
            self.activeCameraID = deviceID

            self.session.commitConfiguration()

            if wasRunning { self.session.startRunning() }
        }
    }

    deinit {
        stop()
    }

    // MARK: - Device Selection
    /// 优先选择外接摄像头，若不可用则使用内置前摄
    private func bestAvailableCamera() -> AVCaptureDevice? {
        let externalDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices
        if !externalDevices.isEmpty {
            return externalDevices.first
        }
        return AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .unspecified
        )
    }

    // MARK: - Session Configuration
    private func configureSession(deviceID: String? = nil) {
        sessionQueue.sync { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.session.sessionPreset = .vga640x480

            // 1. Input – 指定摄像头或自动选择最佳
            let device: AVCaptureDevice?
            if let id = deviceID, !id.isEmpty {
                device = AVCaptureDevice(uniqueID: id)
            } else {
                device = self.bestAvailableCamera()
            }

            guard let selectedDevice = device else {
                print("CameraService: no camera available")
                return
            }

            guard let input = try? AVCaptureDeviceInput(device: selectedDevice),
                  self.session.canAddInput(input) else {
                print("CameraService: could not add camera input")
                return
            }
            self.session.addInput(input)
            self.currentInput = input
            self.activeCameraID = selectedDevice.uniqueID

            // 2. Output – video data
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

            guard self.session.canAddOutput(self.videoOutput) else {
                print("CameraService: could not add video output")
                return
            }
            self.session.addOutput(self.videoOutput)

            self.isConfigured = true
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        currentFrameSize = CGSize(width: CGFloat(CVPixelBufferGetWidth(pb)),
                                  height: CGFloat(CVPixelBufferGetHeight(pb)))
        let now = Date()
        frameTimestamps.append(now)
        if frameTimestamps.count > 10 { frameTimestamps.removeFirst() }
        if frameTimestamps.count >= 2 {
            let interval = now.timeIntervalSince(frameTimestamps.first!)
            if interval > 0 {
                let fps = Double(frameTimestamps.count - 1) / interval
                onFPSUpdate?(fps, frameTimestamps.count)
            }
        }
        onSampleBuffer?(sampleBuffer)
    }
}
