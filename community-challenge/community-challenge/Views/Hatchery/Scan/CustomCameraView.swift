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
    @State private var isDeliveringImage = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                cameraContent

                HatcheryScanGradients(bottomHeight: 246)

                if showsSuggestedBoundary {
                    let suggestion = QuadPoints.defaultShape(in: geometry.size)
                    HatcheryOverlay(
                        quad: .constant(suggestion),
                        isEditable: false
                    )
                }

                // One container for every glass element on screen, so the
                // banner and the controls sample and tint as a single material
                // instead of resolving independently.
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
                isDeliveringImage = false
                if camera.capturedImage != nil {
                    camera.resumeLivePreview()
                }
                camera.start()
            }
            // Reading the size straight from the proxy — rather than caching it
            // in @State on appear — is what stops a photo from being stranded
            // when it arrives before the cached size is populated.
            .onChange(of: camera.capturedImage) { _, image in
                guard let image else { return }
                deliver(image, in: geometry.size)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard
                    let data = try? await newItem.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    pickerItem = nil
                    return
                }

                pickerItem = nil
                camera.present(selectedImage: image)
            }
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
            CameraPreview(session: camera.session)
        }
    }

    private var captureControls: some View {
        HStack(alignment: .center, spacing: 38) {
            HatcheryScanSideControl(
                systemName: "xmark",
                label: "Close",
                action: onClose
            )

            HatcheryScanPrimaryControl {
                camera.capturePhoto()
            }
            .disabled(camera.status != .ready)
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
        }
        .frame(height: 107)
    }

    /// Hands the photo to the flow. This always advances: a degenerate
    /// container size falls back to the normalized default framing rather than
    /// dropping the capture, which previously forced the user to retake.
    private func deliver(_ sourceImage: UIImage, in containerSize: CGSize) {
        guard !isDeliveringImage else { return }
        isDeliveringImage = true

        let image = HatcheryImageProcessor.preparedImage(sourceImage)
        let suggestion: HatcheryBoundary

        if containerSize.width > 0, containerSize.height > 0 {
            let mapper = AspectFillImageMapper(
                imageSize: image.size,
                containerSize: containerSize
            )
            suggestion = mapper.boundary(
                for: QuadPoints.defaultShape(in: containerSize)
            )
        } else {
            suggestion = .defaultSuggestion
        }

        camera.stop()
        onCapture(image, suggestion)
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
}

#Preview("Capture Hatchery", traits: .fixedLayout(width: 402, height: 874)) {
    CustomCameraView(onClose: {}, onCapture: { _, _ in })
}
