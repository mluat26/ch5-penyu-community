@preconcurrency import AVFoundation
import Combine
import ImageIO
import OSLog
import UIKit

/// Back-camera orientation values shared by Vision and still-photo capture.
/// Internal visibility intentionally leaves this deterministic mapping testable.
nonisolated struct HatcheryCameraOrientation: Equatable, Sendable {
    let visionImageOrientation: CGImagePropertyOrientation
    let videoRotationAngle: CGFloat

    static func backCamera(
        for interfaceOrientation: UIInterfaceOrientation
    ) -> HatcheryCameraOrientation {
        switch interfaceOrientation {
        case .portrait:
            return HatcheryCameraOrientation(
                visionImageOrientation: .right,
                videoRotationAngle: 90
            )
        case .portraitUpsideDown:
            return HatcheryCameraOrientation(
                visionImageOrientation: .left,
                videoRotationAngle: 270
            )
        case .landscapeLeft:
            return HatcheryCameraOrientation(
                visionImageOrientation: .up,
                videoRotationAngle: 0
            )
        case .landscapeRight:
            return HatcheryCameraOrientation(
                visionImageOrientation: .down,
                videoRotationAngle: 180
            )
        default:
            return HatcheryCameraOrientation(
                visionImageOrientation: .right,
                videoRotationAngle: 90
            )
        }
    }
}

/// Receives camera frames on one serial queue and keeps Vision work away from
/// both the capture-session queue and the main actor.
nonisolated private final class HatcheryVideoAnalyzer: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {

    typealias DetectionHandler = @Sendable (
        _ generation: UInt,
        _ detection: HatcheryBoundaryDetection?
    ) -> Void

    let queue = DispatchQueue(label: "hatchery.camera.vision", qos: .userInitiated)

    private let detector = HatcheryBoundaryDetector()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "community-challenge",
        category: "HatcheryCameraFrames"
    )
    private let minimumAnalysisInterval = 0.15

    // Accessed only on `queue`.
    private var isActive = false
    private var generation: UInt = 0
    private var orientation: CGImagePropertyOrientation = .right
    private var onDetection: DetectionHandler?
    private var lastAnalysisTimestamp: CMTime = .invalid
    private var droppedFrameCount = 0
    private var throttledFrameCount = 0

    func start(
        generation: UInt,
        orientation: CGImagePropertyOrientation,
        onDetection: @escaping DetectionHandler
    ) {
        queue.async { [self] in
            self.generation = generation
            self.orientation = orientation
            self.onDetection = onDetection
            self.lastAnalysisTimestamp = .invalid
            self.droppedFrameCount = 0
            self.throttledFrameCount = 0
            self.detector.reset()
            self.isActive = true
        }
    }

    func stop() {
        queue.async { [self] in
            self.isActive = false
            self.onDetection = nil
            self.lastAnalysisTimestamp = .invalid
            self.detector.reset()
        }
    }

    func updateOrientation(
        _ orientation: CGImagePropertyOrientation,
        generation: UInt
    ) {
        queue.async { [self] in
            guard self.isActive, self.generation == generation else { return }
            guard self.orientation != orientation else { return }
            self.orientation = orientation
            self.lastAnalysisTimestamp = .invalid
            self.detector.reset()
            self.onDetection?(generation, nil)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isActive else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastAnalysisTimestamp.isValid {
            let elapsed = CMTimeGetSeconds(timestamp - lastAnalysisTimestamp)
            if elapsed.isFinite, elapsed >= 0, elapsed < minimumAnalysisInterval {
                throttledFrameCount += 1
                return
            }
        }
        lastAnalysisTimestamp = timestamp

        if throttledFrameCount >= 30 {
            logger.debug(
                "Throttled camera frames before Vision: \(self.throttledFrameCount, privacy: .public)"
            )
            throttledFrameCount = 0
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let detection = detector.processLive(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        )
        guard isActive else { return }
        onDetection?(generation, detection)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isActive else { return }
        droppedFrameCount += 1
        if droppedFrameCount.isMultiple(of: 30) {
            logger.debug(
                "Dropped camera frames while scanning: \(self.droppedFrameCount, privacy: .public)"
            )
        }
    }
}

/// A lock-protected intent gate lets `stop()` invalidate an in-progress session
/// configuration before its serial-queue work reaches `startRunning()`.
nonisolated private final class HatcheryCameraLifecycleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt = 0
    private var wantsRunning = false

    func update(generation: UInt, wantsRunning: Bool) {
        lock.lock()
        self.generation = generation
        self.wantsRunning = wantsRunning
        lock.unlock()
    }

    func permits(_ generation: UInt) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.generation == generation && wantsRunning
    }
}

/// Owns all mutable AVFoundation configuration state on `queue`.
nonisolated private final class HatcheryCameraSessionCoordinator: @unchecked Sendable {
    typealias DetectionHandler = HatcheryVideoAnalyzer.DetectionHandler
    typealias StartCompletion = @Sendable (_ generation: UInt, _ succeeded: Bool) -> Void
    typealias PhotoCompletion = @Sendable (_ generation: UInt, _ image: UIImage?) -> Void

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoAnalyzer = HatcheryVideoAnalyzer()
    private let queue = DispatchQueue(label: "hatchery.camera.session")
    private let lifecycle = HatcheryCameraLifecycleGate()

    // Accessed only on `queue`.
    private var isConfigured = false

    func start(
        generation: UInt,
        orientation: HatcheryCameraOrientation,
        onDetection: @escaping DetectionHandler,
        completion: @escaping StartCompletion
    ) {
        lifecycle.update(generation: generation, wantsRunning: true)
        queue.async { [self] in
            guard lifecycle.permits(generation) else { return }

            if !isConfigured {
                guard configureSession() else {
                    completion(generation, false)
                    return
                }
                isConfigured = true
            }

            guard lifecycle.permits(generation) else { return }
            applyPhotoOrientation(orientation.videoRotationAngle)
            guard lifecycle.permits(generation) else { return }

            if !session.isRunning {
                session.startRunning()
            }

            // `stop()` can invalidate the generation while `startRunning()` is
            // blocking. In that case, tear down immediately and publish nothing.
            guard lifecycle.permits(generation) else {
                if session.isRunning { session.stopRunning() }
                return
            }

            videoAnalyzer.start(
                generation: generation,
                orientation: orientation.visionImageOrientation,
                onDetection: onDetection
            )
            completion(generation, true)
        }
    }

    func stop(generation: UInt) {
        lifecycle.update(generation: generation, wantsRunning: false)
        videoAnalyzer.stop()
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto(
        generation: UInt,
        completion: @escaping PhotoCompletion
    ) {
        videoAnalyzer.stop()
        queue.async { [self] in
            guard lifecycle.permits(generation), session.isRunning else {
                completion(generation, nil)
                return
            }

            let settings = AVCapturePhotoSettings()
            let processor = HatcheryPhotoProcessor(
                generation: generation,
                completion: completion
            )
            processor.retainUntilCallback()
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    func updateOrientation(
        _ orientation: HatcheryCameraOrientation,
        generation: UInt
    ) {
        videoAnalyzer.updateOrientation(
            orientation.visionImageOrientation,
            generation: generation
        )
        queue.async { [self] in
            guard lifecycle.permits(generation) else { return }
            applyPhotoOrientation(orientation.videoRotationAngle)
        }
    }

    /// Runs only on `queue`.
    private func configureSession() -> Bool {
        session.beginConfiguration()
        var didConfigure = false
        defer {
            if !didConfigure {
                // A later retry must start from a known session state. Leaving
                // a partially-added input or output here makes `canAdd…`
                // fail on the next foreground attempt.
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                let outputs = session.outputs
                outputs.forEach(session.removeOutput)
                let inputs = session.inputs
                inputs.forEach(session.removeInput)
            }
            session.commitConfiguration()
        }

        guard session.canSetSessionPreset(.photo) else { return false }
        session.sessionPreset = .photo

        let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) ?? AVCaptureDevice.default(for: .video)

        guard
            let device,
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [:]
        videoOutput.setSampleBufferDelegate(videoAnalyzer, queue: videoAnalyzer.queue)
        guard session.canAddOutput(videoOutput) else { return false }
        session.addOutput(videoOutput)

        didConfigure = true
        return true
    }

    /// Runs only on `queue`, after photo output configuration has committed.
    private func applyPhotoOrientation(_ rotationAngle: CGFloat) {
        guard
            let connection = photoOutput.connection(with: .video),
            connection.isVideoRotationAngleSupported(rotationAngle)
        else { return }
        connection.videoRotationAngle = rotationAngle
    }
}

/// Per-request delegate carrying an immutable lifecycle generation. AVFoundation
/// retains the delegate for capture; the self-retain covers platform variance.
nonisolated private final class HatcheryPhotoProcessor: NSObject,
    AVCapturePhotoCaptureDelegate,
    @unchecked Sendable {

    private let generation: UInt
    private let completion: HatcheryCameraSessionCoordinator.PhotoCompletion
    private let lock = NSLock()
    private var retainedSelf: HatcheryPhotoProcessor?

    init(
        generation: UInt,
        completion: @escaping HatcheryCameraSessionCoordinator.PhotoCompletion
    ) {
        self.generation = generation
        self.completion = completion
    }

    func retainUntilCallback() {
        lock.lock()
        retainedSelf = self
        lock.unlock()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if
            error == nil,
            let data = photo.fileDataRepresentation()
        {
            image = UIImage(data: data)
        } else {
            image = nil
        }

        completion(generation, image)

        lock.lock()
        retainedSelf = nil
        lock.unlock()
    }
}

/// Owns the camera lifecycle exposed to SwiftUI. All published state remains on
/// the main actor; the coordinator owns session/output state on its serial queue.
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status: Equatable {
        case unknown
        case unauthorized
        case configuring
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .unknown
    @Published var capturedImage: UIImage?
    @Published private(set) var liveDetection: HatcheryBoundaryDetection?
    @Published private(set) var isCapturingPhoto = false

    let session: AVCaptureSession

    private let coordinator: HatcheryCameraSessionCoordinator
    private var lifecycleGeneration: UInt = 0
    private var wantsRunning = false
    private var acceptsLiveDetection = false
    private var interfaceOrientation: UIInterfaceOrientation = .portrait

    override init() {
        let coordinator = HatcheryCameraSessionCoordinator()
        self.coordinator = coordinator
        self.session = coordinator.session
        super.init()
    }

    /// Requests authorization (if needed), configures the session once, and
    /// starts it running. Safe to call every time the camera view appears.
    func start() {
        // SwiftUI can issue repeated active-scene updates while the session is
        // configuring. Keep the original request alive rather than creating a
        // new lifecycle generation underneath it.
        guard !wantsRunning else { return }

        #if targetEnvironment(simulator)
        status = .failed(
            "Live camera scanning needs a physical iPhone. Select a hatchery photo below to continue."
        )
        #else
        let generation = beginRunningIntent()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun(generation: generation)
        case .notDetermined:
            status = .configuring
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard
                        let self,
                        self.wantsRunning,
                        self.lifecycleGeneration == generation
                    else { return }

                    if granted {
                        self.configureAndRun(generation: generation)
                    } else {
                        self.wantsRunning = false
                        self.status = .unauthorized
                        self.coordinator.stop(generation: generation)
                    }
                }
            }
        default:
            wantsRunning = false
            status = .unauthorized
            coordinator.stop(generation: generation)
        }
        #endif
    }

    /// Stops the session and invalidates permission/configuration callbacks that
    /// were issued by an earlier appearance.
    func stop() {
        wantsRunning = false
        lifecycleGeneration &+= 1
        acceptsLiveDetection = false
        liveDetection = nil
        isCapturingPhoto = false
        coordinator.stop(generation: lifecycleGeneration)
    }

    func capturePhoto() {
        guard status == .ready, wantsRunning, !isCapturingPhoto else { return }

        let generation = lifecycleGeneration
        isCapturingPhoto = true
        acceptsLiveDetection = false
        coordinator.capturePhoto(generation: generation) { [weak self] generation, image in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.wantsRunning,
                    self.lifecycleGeneration == generation,
                    self.isCapturingPhoto
                else { return }

                self.isCapturingPhoto = false
                guard let image else {
                    self.resumeLivePreview()
                    return
                }

                self.capturedImage = image
                self.stop()
            }
        }
    }

    /// Clears the captured image so the live preview can resume (Retake).
    func resumeLivePreview() {
        capturedImage = nil
        isCapturingPhoto = false
        start()
    }

    /// Shows an image chosen from the photo library instead of a live capture,
    /// stopping the session while it is reviewed.
    func present(selectedImage image: UIImage) {
        capturedImage = image
        stop()
    }

    /// Keeps Vision and still-photo orientation aligned with the preview.
    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        guard orientation != .unknown else { return }
        guard interfaceOrientation != orientation else { return }

        interfaceOrientation = orientation
        liveDetection = nil
        coordinator.updateOrientation(
            HatcheryCameraOrientation.backCamera(for: orientation),
            generation: lifecycleGeneration
        )
    }

    private func beginRunningIntent() -> UInt {
        lifecycleGeneration &+= 1
        wantsRunning = true
        acceptsLiveDetection = false
        liveDetection = nil
        isCapturingPhoto = false
        return lifecycleGeneration
    }

    private func configureAndRun(generation: UInt) {
        guard wantsRunning, lifecycleGeneration == generation else { return }
        status = .configuring

        let orientation = HatcheryCameraOrientation.backCamera(for: interfaceOrientation)
        coordinator.start(
            generation: generation,
            orientation: orientation,
            onDetection: { [weak self] generation, detection in
                Task { @MainActor [weak self] in
                    guard
                        let self,
                        self.wantsRunning,
                        self.lifecycleGeneration == generation,
                        self.acceptsLiveDetection,
                        self.status == .ready
                    else { return }
                    self.liveDetection = detection
                }
            },
            completion: { [weak self] generation, succeeded in
                Task { @MainActor [weak self] in
                    guard
                        let self,
                        self.wantsRunning,
                        self.lifecycleGeneration == generation
                    else { return }

                    if succeeded {
                        self.acceptsLiveDetection = true
                        self.status = .ready
                    } else {
                        self.wantsRunning = false
                        self.acceptsLiveDetection = false
                        self.status = .failed(
                            "Couldn’t start the camera. Check the device camera and try again, or select a hatchery photo below."
                        )
                        self.coordinator.stop(generation: generation)
                    }
                }
            }
        )
    }
}
