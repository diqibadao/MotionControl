import SwiftUI
import AVFoundation

/// 摄像头预览视图（NSViewRepresentable）
public struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.videoGravity = .resizeAspectFill
        view.layer?.addSublayer(previewLayer)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // 更新 layer 尺寸
        if let layer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = nsView.bounds
        }
    }
}
