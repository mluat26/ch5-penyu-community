import AVFoundation
import SwiftUI

/// A SwiftUI wrapper around `AVCaptureVideoPreviewLayer` that renders the
/// live feed from a running `AVCaptureSession`.
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    let interfaceOrientation: UIInterfaceOrientation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        updateOrientation(of: view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        updateOrientation(of: uiView.videoPreviewLayer)
    }

    private func updateOrientation(of previewLayer: AVCaptureVideoPreviewLayer) {
        let angle = HatcheryCameraOrientation
            .backCamera(for: interfaceOrientation)
            .videoRotationAngle

        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle)
        else { return }
        connection.videoRotationAngle = angle
    }

    /// A `UIView` backed by an `AVCaptureVideoPreviewLayer`, so the preview
    /// resizes correctly with Auto Layout / SwiftUI frames.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Safe: layerClass guarantees this type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
