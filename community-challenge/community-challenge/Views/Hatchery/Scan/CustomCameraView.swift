import ImageIO
import OSLog
import PhotosUI
import SwiftUI

/// Captures or selects the hatchery photo, then advances immediately.
///
/// The green quadrilateral is only a read-only framing suggestion here. The
/// same image-relative boundary is passed to `HatcheryBoundaryAdjustmentView`,
/// where the user can edit it.
struct CustomCameraView: View {
    let onClose: () -> Void
    let onCapture: (UIImage, HatcheryBoundary) -> Void

    @StateObject private var camera = CameraManager()
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewSize: CGSize = .zero
    @State private var pendingDelivery: PendingDelivery?
    @State private var activeRequest: ImageRequest?
    @State private var pickerLoadTask: Task<Void, Never>?
    @State private var isDeliveringImage = false
    @State private var isLoadingPicker = false
    @State private var deliveryTask: Task<Void, Never>?
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "community-challenge",
        category: "HatcheryCapture"
    )

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                cameraContent

                HatcheryScanGradients(bottomHeight: 246)

                if showsSuggestedBoundary {
                    HatcheryOverlay(
                        quad: .constant(suggestedQuad(in: geometry.size)),
                        isEditable: false
                    )
                }

                GlassEffectContainer(spacing: 20) {
                    VStack(spacing: 0) {
                        HatcheryScanInstructionBanner(
                            systemName: "camera.viewfinder",
                            text: "Get ready to check out the whole turtle hatching area"
                        )
                        .padding(.top, 68)

                        Spacer(minLength: 0)

                        captureControls
                            .padding(.bottom, 59)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                invalidatePendingWork()
                previewSize = geometry.size
                updateInterfaceOrientation()
                if camera.capturedImage != nil {
                    camera.resumeLivePreview()
                } else {
                    camera.start()
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                previewSize = newSize
                updateInterfaceOrientation()
                if let pendingDelivery {
                    deliver(pendingDelivery.image, for: pendingDelivery.request)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateInterfaceOrientation()
        }
        .onDisappear {
            invalidatePendingWork()
            camera.stop()
        }
        .onChange(of: camera.capturedImage) { _, image in
            guard
                let image,
                let request = activeRequest,
                case .camera = request.source
            else { return }
            deliver(image, for: request)
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            loadPickerItem(newItem)
        }
    }

    private var showsSuggestedBoundary: Bool {
        switch camera.status {
        case .unauthorized, .failed:
            return false
        default:
            return camera.capturedImage == nil
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch camera.status {
        case .unauthorized:
            unauthorizedView
        case .failed(let message):
            messageView(message)
        default:
            CameraPreview(
                session: camera.session,
                interfaceOrientation: interfaceOrientation
            )
        }
    }

    private var captureControls: some View {
        HStack(alignment: .center, spacing: 38) {
            HatcheryScanSideControl(
                systemName: "xmark",
                label: "Close",
                action: close
            )

            HatcheryScanPrimaryControl {
                captureCurrentFrame()
            }
            .disabled(!canCapturePhoto)
            .opacity(camera.status == .ready ? 1 : 0.5)

            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HatcheryScanSideLabel(
                    systemName: "photo.on.rectangle",
                    label: "Select"
                )
            }
            .buttonStyle(.plain)
            .frame(width: 72, height: 78)
            .disabled(
                camera.isCapturingPhoto
                    || isLoadingPicker
                    || isDeliveringImage
            )
        }
        .frame(height: 107)
    }

    private var canCapturePhoto: Bool {
        camera.status == .ready
            && !camera.isCapturingPhoto
            && !isLoadingPicker
            && !isDeliveringImage
    }

    private func deliver(_ sourceImage: UIImage, for request: ImageRequest) {
        guard activeRequest?.id == request.id else { return }
        guard !isDeliveringImage else { return }
        guard previewSize.width > 0, previewSize.height > 0 else {
            pendingDelivery = PendingDelivery(image: sourceImage, request: request)
            return
        }

        isDeliveringImage = true
        pendingDelivery = nil

        let canvasSize = previewSize
        let snapshot = request.snapshot ?? CaptureSnapshot.default(in: canvasSize)

        deliveryTask?.cancel()
        let processingTask = Task.detached(priority: .userInitiated) {
            let image = HatcheryImageProcessor.preparedImage(sourceImage)
            let mapper = AspectFillImageMapper(
                imageSize: image.size,
                containerSize: canvasSize
            )
            let fallbackBoundary = mapper.boundary(for: snapshot.quad)

            let stillDetection = image.cgImage.flatMap { cgImage in
                HatcheryBoundaryDetector().detectStill(
                    cgImage: cgImage,
                    orientation: .up
                )
            }

            let selection = HatcheryCaptureBoundarySelector.select(
                stillDetection: stillDetection,
                liveBoundary: snapshot.cameFromLiveDetection ? fallbackBoundary : nil,
                fallbackBoundary: fallbackBoundary
            )
            return DeliveryResult(
                image: image,
                boundary: selection.boundary,
                source: selection.source
            )
        }
        deliveryTask = Task {
            let result = await withTaskCancellationHandler {
                await processingTask.value
            } onCancel: {
                processingTask.cancel()
            }

            guard
                !Task.isCancelled,
                activeRequest?.id == request.id
            else { return }
            activeRequest = nil
            isDeliveringImage = false
            logger.debug("Hatchery capture boundary source: \(result.source.rawValue, privacy: .public)")
            camera.stop()
            onCapture(result.image, result.boundary)
        }
    }

    private func captureCurrentFrame() {
        guard canCapturePhoto else { return }

        pickerLoadTask?.cancel()
        pickerLoadTask = nil
        pickerItem = nil
        isLoadingPicker = false

        let snapshot = previewSize.width > 0 && previewSize.height > 0
            ? CaptureSnapshot(
                quad: suggestedQuad(in: previewSize),
                cameFromLiveDetection: camera.liveDetection != nil
            )
            : nil
        activeRequest = ImageRequest(
            id: UUID(),
            source: .camera(snapshot)
        )
        camera.capturePhoto()
    }

    private func loadPickerItem(_ item: PhotosPickerItem) {
        pickerLoadTask?.cancel()
        deliveryTask?.cancel()
        pendingDelivery = nil
        isDeliveringImage = false

        let request = ImageRequest(id: UUID(), source: .photoLibrary)
        activeRequest = request
        isLoadingPicker = true

        pickerLoadTask = Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                !Task.isCancelled,
                activeRequest?.id == request.id,
                let image = UIImage(data: data)
            else {
                if activeRequest?.id == request.id {
                    activeRequest = nil
                    isLoadingPicker = false
                    pickerItem = nil
                }
                return
            }

            pickerLoadTask = nil
            pickerItem = nil
            isLoadingPicker = false
            camera.present(selectedImage: image)
            deliver(image, for: request)
        }
    }

    private func close() {
        invalidatePendingWork()
        onClose()
    }

    private func invalidatePendingWork() {
        pickerLoadTask?.cancel()
        deliveryTask?.cancel()
        pickerLoadTask = nil
        deliveryTask = nil
        activeRequest = nil
        pendingDelivery = nil
        isLoadingPicker = false
        isDeliveringImage = false
    }

    private func suggestedQuad(in canvasSize: CGSize) -> QuadPoints {
        guard let detection = camera.liveDetection else {
            return QuadPoints.defaultShape(in: canvasSize)
        }

        let mapper = AspectFillImageMapper(
            imageSize: detection.orientedImageSize,
            containerSize: canvasSize
        )
        return mapper.viewQuad(for: detection.boundary)
    }

    private func updateInterfaceOrientation() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let orientation = scene.effectiveGeometry.interfaceOrientation
        interfaceOrientation = orientation
        camera.updateInterfaceOrientation(orientation)
    }

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.appOffWhite)

            Text("Camera access is off")
                .font(.headline)
                .foregroundStyle(Color.appOffWhite)

            Text("Enable camera access in Settings, or select a hatchery photo below.")
                .font(.subheadline)
                .foregroundStyle(Color.appOffWhite.opacity(0.8))
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.headline)
            .foregroundStyle(Color.appGreenPrimary)
            .padding(.top, 8)
        }
        .padding(32)
    }

    private func messageView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.appYellow)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appOffWhite)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private struct CaptureSnapshot {
        let quad: QuadPoints
        let cameFromLiveDetection: Bool

        static func `default`(in canvasSize: CGSize) -> CaptureSnapshot {
            CaptureSnapshot(
                quad: QuadPoints.defaultShape(in: canvasSize),
                cameFromLiveDetection: false
            )
        }
    }

    private enum ImageRequestSource {
        case camera(CaptureSnapshot?)
        case photoLibrary
    }

    private struct ImageRequest {
        let id: UUID
        let source: ImageRequestSource

        var snapshot: CaptureSnapshot? {
            guard case .camera(let snapshot) = source else { return nil }
            return snapshot
        }
    }

    private struct PendingDelivery {
        let image: UIImage
        let request: ImageRequest
    }

    private struct DeliveryResult {
        let image: UIImage
        let boundary: HatcheryBoundary
        let source: HatcheryCaptureBoundarySource
    }
}

nonisolated enum HatcheryCaptureBoundarySource: String {
    case stillRefinement
    case liveSnapshot
    case stillDetection
    case defaultGuide
}

nonisolated enum HatcheryCaptureBoundarySelector {
    struct Selection: Equatable {
        let boundary: HatcheryBoundary
        let source: HatcheryCaptureBoundarySource
    }

    static func select(
        stillDetection: HatcheryBoundaryDetection?,
        liveBoundary: HatcheryBoundary?,
        fallbackBoundary: HatcheryBoundary,
        maximumRefinementDistance: Double = 0.10
    ) -> Selection {
        if let liveBoundary {
            if let stillDetection,
               meanCornerDistance(stillDetection.boundary, liveBoundary)
                <= maximumRefinementDistance {
                return Selection(
                    boundary: stillDetection.boundary,
                    source: .stillRefinement
                )
            }
            return Selection(boundary: liveBoundary, source: .liveSnapshot)
        }

        if let stillDetection {
            return Selection(
                boundary: stillDetection.boundary,
                source: .stillDetection
            )
        }
        return Selection(boundary: fallbackBoundary, source: .defaultGuide)
    }

    private static func meanCornerDistance(
        _ first: HatcheryBoundary,
        _ second: HatcheryBoundary
    ) -> Double {
        zip(first.ordered, second.ordered)
            .map { lhs, rhs in
                let dx = lhs.x - rhs.x
                let dy = lhs.y - rhs.y
                return (dx * dx + dy * dy).squareRoot()
            }
            .reduce(0, +) / 4
    }
}

#Preview("Capture Hatchery", traits: .fixedLayout(width: 402, height: 874)) {
    CustomCameraView(onClose: {}, onCapture: { _, _ in })
}
