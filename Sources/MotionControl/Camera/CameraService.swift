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
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 设置分辨率为 VGA 640x480

        // 1. Input – 优先外接摄像头
        guard let device = bestAvailableCamera() else {
            print("CameraService: no camera available")
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("CameraService: could not add camera input")
            return
        }
        session.addInput(input)

        // 2. Output – video data
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(videoOutput) else {
            print("CameraService: could not add video output")
            return
        }
        session.addOutput(videoOutput)

        isConfigured = true
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer?(sampleBuffer)
    }
}
