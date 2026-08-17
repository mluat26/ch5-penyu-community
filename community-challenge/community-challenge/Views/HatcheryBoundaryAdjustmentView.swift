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
    @State private var canvasSize: CGSize = .zero
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

                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()

                HatcheryScanGradients(bottomHeight: 337)

                HatcherySandRegionOverlay(
                    region: $sandRegion,
                    imageSize: image.size,
                    fallbackBoundary: boundary,
                    isEditable: !isConfirming
                )

                GlassEffectContainer(spacing: 20) {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
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

    private func replaceImage(with sourceImage: UIImage, requestID: UUID) {
        let targetCanvasSize = canvasSize
        let fallbackQuad = targetCanvasSize.width > 0 && targetCanvasSize.height > 0
            ? QuadPoints.defaultShape(in: targetCanvasSize)
            : nil
        replacementTask?.cancel()
        let processingTask = Task.detached(priority: .userInitiated) {
            let preparedImage = HatcheryImageProcessor.preparedImage(sourceImage)
            let detectedBoundary = preparedImage.cgImage.flatMap { cgImage in
                HatcheryBoundaryDetector().detectStill(
                    cgImage: cgImage,
                    orientation: .up
                )?.boundary
            }

            guard let fallbackQuad else {
                return ReplacementResult(
                    image: preparedImage,
                    boundary: detectedBoundary ?? .fullImage
                )
            }

            let mapper = AspectFillImageMapper(
                imageSize: preparedImage.size,
                containerSize: targetCanvasSize
            )
            let fallback = mapper.boundary(
                for: fallbackQuad
            )
            return ReplacementResult(
                image: preparedImage,
                boundary: detectedBoundary ?? fallback
            )
        }
        replacementTask = Task {
            let result = await withTaskCancellationHandler {
                await processingTask.value
            } onCancel: {
                processingTask.cancel()
            }

            guard
                !Task.isCancelled,
                replacementRequestID == requestID
            else { return }
            image = result.image
            boundary = result.boundary
            sandRegion = HatcherySandRegion.default(from: result.boundary)
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

    private struct ReplacementResult {
        let image: UIImage
        let boundary: HatcheryBoundary
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
