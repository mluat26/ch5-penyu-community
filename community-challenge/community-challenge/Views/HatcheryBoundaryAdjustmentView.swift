import PhotosUI
import SwiftUI

/// The dedicated boundary-editing step shown after a hatchery photo is made.
struct HatcheryBoundaryAdjustmentView: View {
    let onRetake: () -> Void
    let onConfirm: (UIImage, HatcheryBoundary, HatcherySandRegion) async -> Void

    @State private var image: UIImage
    /// The four-point perspective plane is intentionally not editable here.
    /// It is used later to rectify the photo and project the logical grid.
    @State private var boundary: HatcheryBoundary
    /// The user edits this many-point polygon to describe usable sand.
    @State private var sandRegion: HatcherySandRegion?
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerLoadTask: Task<Void, Never>?
    @State private var replacementTask: Task<Void, Never>?
    @State private var replacementRequestID: UUID?
    @State private var isReplacingImage = false
    @State private var isConfirming = false
    @State private var confirmationTask: Task<Void, Never>?

    init(
        image: UIImage,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil,
        onRetake: @escaping () -> Void,
        onConfirm: @escaping (UIImage, HatcheryBoundary, HatcherySandRegion) async -> Void
    ) {
        _image = State(initialValue: image)
        _boundary = State(initialValue: boundary)
        _sandRegion = State(
            initialValue: sandRegion ?? HatcherySandRegion.default(from: boundary)
        )
        self.onRetake = onRetake
        self.onConfirm = onConfirm
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                // Fitted, not filled. This is the screen where the sand
                // outline is dragged, and `scaledToFill` cropped part of the
                // photo away -- you cannot place a vertex on sand you cannot
                // see, so the crop silently limited the editable area.
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    .clipped()

                HatcheryScanGradients(bottomHeight: 337)

                HatcherySandRegionOverlay(
                    region: $sandRegion,
                    imageSize: image.size,
                    fallbackBoundary: boundary,
                    isEditable: !isConfirming,
                    contentMode: .fit
                )

                VStack(spacing: 0) {
                    HatcheryScanInstructionBanner(
                        systemName: "hand.draw.fill",
                        text: "Adjust the sand area to fit inside your hatchery area"
                    )
                    .padding(.top, 68)

                    Spacer(minLength: 0)

                    adjustmentControls
                        .padding(.bottom, 59)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            cancelReplacement()
            confirmationTask?.cancel()
            confirmationTask = nil
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            loadPickerItem(newItem)
        }
    }

    private var adjustmentControls: some View {
        HStack(alignment: .center, spacing: 38) {
            HatcheryScanSideControl(
                systemName: "chevron.left",
                label: "Retake",
                action: retake
            )
            .disabled(isConfirming)

            ZStack {
                HatcheryScanPrimaryControl(systemName: isConfirming ? nil : "checkmark") {
                    confirm()
                }

                if isConfirming {
                    ProgressView()
                        .tint(Color.appGreenPrimary)
                        .frame(width: 87, height: 87)
                }
            }
            .disabled(!(sandRegion?.isValid ?? false) || isReplacingImage || isConfirming)
            .opacity((sandRegion?.isValid ?? false) ? 1 : 0.5)

            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HatcheryScanSideLabel(
                    systemName: "photo.on.rectangle",
                    label: "Replace"
                )
            }
            .buttonStyle(.plain)
            .frame(width: 72, height: 78)
            .disabled(isReplacingImage)
            .disabled(isConfirming)
        }
        .frame(height: 107)
    }

    private func loadPickerItem(_ item: PhotosPickerItem) {
        cancelReplacement()

        let requestID = UUID()
        replacementRequestID = requestID
        isReplacingImage = true

        pickerLoadTask = Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                !Task.isCancelled,
                replacementRequestID == requestID,
                let selectedImage = UIImage(data: data)
            else {
                if replacementRequestID == requestID {
                    finishReplacement()
                }
                return
            }

            pickerLoadTask = nil
            pickerItem = nil
            replaceImage(with: selectedImage, requestID: requestID)
        }
    }

    /// Takes a library photo exactly the way a camera capture is taken.
    ///
    /// A capture hands over the raw image and its boundary, and
    /// `confirmBoundary` prepares and rectifies it once. This path used to do
    /// more: it ran `preparedImage` itself, then `detectStill` on the result,
    /// and adopted whatever quadrilateral that found. Two consequences, both
    /// gallery-only. The image was prepared twice, and -- far worse -- an
    /// arbitrary photo has no hatchery in it, so the rectangle detector
    /// returned whatever edges happened to be strongest. That quad became the
    /// perspective boundary, and `CIPerspectiveCorrection` dutifully un-skewed
    /// a skew that was never there.
    ///
    /// A library photo has no geometry worth guessing. `.fullImage` makes
    /// rectification an identity transform, so the photo is shown exactly as
    /// picked and the corners are dragged by hand -- which is what the screen
    /// asks for anyway.
    private func replaceImage(with sourceImage: UIImage, requestID: UUID) {
        replacementTask?.cancel()
        replacementTask = Task {
            guard replacementRequestID == requestID else { return }

            // Landscape before the corners are dragged, for the same reason a
            // capture is: the outline is stored as fractions of this photo.
            image = HatcheryImageProcessor.landscapeOriented(sourceImage)
            boundary = .fullImage
            sandRegion = HatcherySandRegion.default(from: .fullImage)
            finishReplacement()
        }
    }

    private func retake() {
        guard !isConfirming else { return }
        cancelReplacement()
        onRetake()
    }

    private func confirm() {
        guard
            let sandRegion,
            sandRegion.isValid,
            !isReplacingImage,
            !isConfirming
        else { return }

        isConfirming = true
        let confirmedImage = image
        let confirmedBoundary = boundary
        confirmationTask = Task {
            await onConfirm(confirmedImage, confirmedBoundary, sandRegion)
            guard !Task.isCancelled else { return }
            isConfirming = false
            confirmationTask = nil
        }
    }

    private func cancelReplacement() {
        pickerLoadTask?.cancel()
        replacementTask?.cancel()
        pickerLoadTask = nil
        replacementTask = nil
        replacementRequestID = nil
        isReplacingImage = false
    }

    private func finishReplacement() {
        pickerLoadTask = nil
        replacementTask = nil
        replacementRequestID = nil
        isReplacingImage = false
        pickerItem = nil
    }

}

#Preview("Adjust Hatchery", traits: .fixedLayout(width: 402, height: 874)) {
    HatcheryBoundaryAdjustmentView(
        image: UIImage(named: "HatcherySamplePhoto") ?? UIImage(),
        boundary: HatcheryBoundary(
            topLeft: NormalizedPoint(x: 0.28, y: 0.30),
            topRight: NormalizedPoint(x: 0.71, y: 0.30),
            bottomRight: NormalizedPoint(x: 0.84, y: 0.67),
            bottomLeft: NormalizedPoint(x: 0.17, y: 0.67)
        ),
        onRetake: {},
        onConfirm: { _, _, _ in }
    )
}
