import AVFoundation
import Foundation

class CameraService: NSObject {
    // MARK: - Properties
    private let session = AVCaptureSession()
    var cameraSession: AVCaptureSession { session }
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false

    /// Callback invoked every time a new video frame is captured.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    /// Callback invoked with current FPS and the number of timestamps used.
    var onFPSUpdate: ((Double, Int) -> Void)?
    private var frameTimestamps: [Date] = []

    /// 当前帧的尺寸（像素）
    var currentFrameSize: CGSize? = nil

    // MARK: - Public API
    func start() {
        if !isConfigured {
            configureSession()
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
    private func configureSession() {
        sessionQueue.sync { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            // 设置分辨率为 VGA 640x480
            self.session.sessionPreset = .vga640x480

            // 1. Input – 优先外接摄像头
            guard let device = self.bestAvailableCamera() else {
                print("CameraService: no camera available")
                return
            }

            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                print("CameraService: could not add camera input")
                return
            }
            self.session.addInput(input)

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
