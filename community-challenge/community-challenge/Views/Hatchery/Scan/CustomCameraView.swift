import SwiftUI
import PhotosUI

/// Phases 1–3 — the custom hatchery scanning camera.
///
/// - Live mode: full-screen preview with a Close / shutter / Select bar.
/// - Review mode (after capture or photo selection): the still image is shown
///   with the draggable hatchery quadrilateral and a Retake / Confirm / Select
///   bar. The instruction banner updates to match the mode.
struct CustomCameraView: View {

    var onClose: () -> Void = {}
    /// Called when the user confirms the framed hatchery area.
    /// Normalization into a `HatcheryBoundary` happens in Phase 4.
    var onConfirm: (UIImage, QuadPoints) -> Void = { _, _ in }

    @StateObject private var camera = CameraManager()

    /// The hatchery quadrilateral drawn over the preview / image (Phase 2).
    /// `nil` until the overlay seeds it on first layout.
    @State private var quad: QuadPoints?

    /// Selected item from the photo library (Phase 3).
    @State private var pickerItem: PhotosPickerItem?

    /// True once a still image (captured or selected) is being reviewed.
    private var isReviewing: Bool { camera.capturedImage != nil }

    /// Whether the quad overlay should be shown (any state that isn't an error).
    private var isPreviewing: Bool {
        switch camera.status {
        case .unauthorized, .failed: return false
        default: return true
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // MARK: - Live camera / captured image / states

            switch camera.status {
            case .unauthorized:
                unauthorizedView
            case .failed(let message):
                messageView(message)
            default:
                if let image = camera.capturedImage {
                    // Bound the image to the screen and clip overflow, otherwise
                    // `.scaledToFill()` expands the ZStack and pushes the banner
                    // and control bar off-screen.
                    Color.clear
                        .overlay(
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipped()
                        .ignoresSafeArea()
                } else {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                }
            }

            // MARK: - Hatchery quadrilateral overlay (Phase 2)

            if isPreviewing {
                HatcheryOverlay(quad: $quad)
                    .ignoresSafeArea()
            }

            // MARK: - Overlays

            VStack {
                instructionBanner
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack {
                Spacer()
                controlBar
            }
        }
        .statusBarHidden(true)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    camera.present(selectedImage: image)
                }
            }
        }
    }

    // MARK: - Instruction Banner

    private var instructionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: isReviewing ? "hand.point.up.left.fill" : "camera.viewfinder")
                .font(.title)
                .foregroundStyle(Color.appOffWhite)

            Text(isReviewing
                 ? "Adjust the area to fit into your\nhatchery area"
                 : "Get ready to check out the whole\nturtle hatching area")
                .font(.body)
                .foregroundStyle(Color.appOffWhite)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    // MARK: - Bottom Control Bar

    private var controlBar: some View {
        HStack {
            if isReviewing {
                // Retake
                controlButton(
                    systemName: "chevron.backward",
                    label: "Retake"
                ) { camera.resumeLivePreview() }

                Spacer()

                // Confirm
                confirmButton

                Spacer()

                // Select another photo
                selectPhotosButton
            } else {
                // Close
                controlButton(
                    systemName: "xmark",
                    label: "Close",
                    action: onClose
                )

                Spacer()

                // Shutter
                shutterButton

                Spacer()

                // Select from Photos
                selectPhotosButton
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(
            // Dark gradient behind the controls that extends past the safe
            // area, so the feed never shows through the bottom strip.
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }

    private var shutterButton: some View {
        Button {
            camera.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 107, height: 107)
                    .glassEffect()
                Circle()
                    .fill(Color.white)
                    .frame(width: 87, height: 87)
            }
        }
        .disabled(camera.status != .ready)
        .opacity(camera.status == .ready ? 1.0 : 0.5)
    }

    private var confirmButton: some View {
        Button {
            if let image = camera.capturedImage, let quad {
                onConfirm(image, quad)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 107, height: 107)
                    .glassEffect()
                Circle()
                    .fill(Color.white)
                    .frame(width: 87, height: 87)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.appGreenPrimary)
            }
        }
    }

    private var selectPhotosButton: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            controlLabel(systemName: "photo.on.rectangle", label: "Select")
        }
    }

    private func controlButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            controlLabel(systemName: systemName, label: label)
        }
    }

    private func controlLabel(systemName: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .frame(width: 52, height: 52)
                .glassEffect()
                .font(.title3)
                .foregroundStyle(Color.appOffWhite)

            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.appOffWhite.opacity(0.9))
        }
    }

    // MARK: - Permission / Error states

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.appOffWhite)

            Text("Camera access is off")
                .font(.headline)
                .foregroundStyle(Color.appOffWhite)

            Text("Enable camera access in Settings to scan your hatchery area.")
                .font(.subheadline)
                .foregroundStyle(Color.appOffWhite.opacity(0.8))
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
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

#Preview {
    CustomCameraView()
}
