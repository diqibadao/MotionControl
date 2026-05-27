import AVFoundation
import Foundation

public class CameraService: NSObject {
    // MARK: - Properties
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false

    /// Callback invoked every time a new video frame is captured.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    // MARK: - Public API
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
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

    // MARK: - Session Configuration
    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1. Input – front camera
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            print("CameraService: front camera unavailable")
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
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer?(sampleBuffer)
    }
}
