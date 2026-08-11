import AVFoundation
import Combine
import UIKit

/// Owns the AVCaptureSession and photo output for the hatchery scanning camera.
///
/// This is intentionally UI-agnostic: it exposes the `session` for a preview
/// layer, a `capturePhoto` entry point, and publishes the captured `UIImage`
/// plus authorization state so SwiftUI can react.
@MainActor
final class CameraManager: NSObject, ObservableObject {

    enum Status: Equatable {
        case unknown
        case unauthorized
        case configuring
        case ready
        case failed(String)
    }

    // MARK: - Published state

    @Published private(set) var status: Status = .unknown
    @Published var capturedImage: UIImage?

    // MARK: - Capture objects

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "hatchery.camera.session")
    private var isConfigured = false

    // MARK: - Lifecycle

    /// Requests authorization (if needed), configures the session once, and
    /// starts it running. Safe to call every time the camera view appears.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            status = .configuring
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.status = .unauthorized
                    }
                }
            }
        default:
            status = .unauthorized
        }
    }

    /// Stops the session. Call when leaving the live camera (e.g. after capture).
    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard status == .ready else { return }
        let settings = AVCapturePhotoSettings()
        sessionQueue.async { [photoOutput] in
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Clears the captured image so the live preview can resume (Retake).
    func resumeLivePreview() {
        capturedImage = nil
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    /// Shows an image chosen from the photo library instead of a live capture,
    /// stopping the session while it is reviewed.
    func present(selectedImage image: UIImage) {
        capturedImage = image
        stop()
    }

    // MARK: - Configuration

    private func configureAndRun() {
        status = .configuring
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                let ok = self.configureSession()
                self.isConfigured = ok
                if !ok {
                    Task { @MainActor in self.status = .failed("Unable to configure camera.") }
                    return
                }
            }

            if !self.session.isRunning { self.session.startRunning() }
            Task { @MainActor in self.status = .ready }
        }
    }

    /// Runs on `sessionQueue`. Returns whether configuration succeeded.
    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)

        return true
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else { return }

        Task { @MainActor in
            self.capturedImage = image
            self.stop()
        }
    }
}
