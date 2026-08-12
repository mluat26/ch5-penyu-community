import PhotosUI
import SwiftUI

/// The dedicated boundary-editing step shown after a hatchery photo is made.
struct HatcheryBoundaryAdjustmentView: View {
    let onRetake: () -> Void
    let onConfirm: (UIImage, HatcheryBoundary) -> Void

    @State private var image: UIImage
    @State private var boundary: HatcheryBoundary
    @State private var pickerItem: PhotosPickerItem?
    @State private var canvasSize: CGSize = .zero

    init(
        image: UIImage,
        boundary: HatcheryBoundary,
        onRetake: @escaping () -> Void,
        onConfirm: @escaping (UIImage, HatcheryBoundary) -> Void
    ) {
        _image = State(initialValue: image)
        _boundary = State(initialValue: boundary)
        self.onRetake = onRetake
        self.onConfirm = onConfirm
    }

    var body: some View {
        GeometryReader { geometry in
            let mapper = AspectFillImageMapper(
                imageSize: image.size,
                containerSize: geometry.size
            )

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

                HatcheryOverlay(
                    quad: boundaryBinding(using: mapper),
                    isEditable: true
                )

                GlassEffectContainer(spacing: 20) {
                    VStack(spacing: 0) {
                        HatcheryScanInstructionBanner(
                            systemName: "hand.draw.fill",
                            text: "Adjust the area to fit into your hatchery area"
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
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard
                    let data = try? await newItem.loadTransferable(type: Data.self),
                    let selectedImage = UIImage(data: data)
                else {
                    pickerItem = nil
                    return
                }

                pickerItem = nil
                replaceImage(with: selectedImage)
            }
        }
    }

    private var adjustmentControls: some View {
        HStack(alignment: .center, spacing: 38) {
            HatcheryScanSideControl(
                systemName: "chevron.left",
                label: "Retake",
                action: onRetake
            )

            HatcheryScanPrimaryControl(systemName: "checkmark") {
                onConfirm(image, boundary)
            }
            .disabled(!boundary.isValid)
            .opacity(boundary.isValid ? 1 : 0.5)

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

    private func boundaryBinding(
        using mapper: AspectFillImageMapper
    ) -> Binding<QuadPoints?> {
        Binding(
            get: { mapper.viewQuad(for: boundary) },
            set: { quad in
                guard let quad else { return }
                boundary = mapper.boundary(for: quad)
            }
        )
    }

    private func replaceImage(with sourceImage: UIImage) {
        let preparedImage = HatcheryImageProcessor.preparedImage(sourceImage)
        image = preparedImage

        guard canvasSize.width > 0, canvasSize.height > 0 else {
            boundary = .fullImage
            return
        }

        let mapper = AspectFillImageMapper(
            imageSize: preparedImage.size,
            containerSize: canvasSize
        )
        boundary = mapper.boundary(
            for: QuadPoints.defaultShape(in: canvasSize)
        )
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
        onConfirm: { _, _ in }
    )
}
