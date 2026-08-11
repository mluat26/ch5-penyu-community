import SwiftUI

struct OnboardingFlowController: View {
    private enum Step: Hashable {
        case scan
        case camera(UUID)
        case adjustBoundary
        case dimensions
        case preview
    }

    let onSave: (SavedHatchery) -> Void

    @State private var path: [Step] = []
    @State private var draft = HatcherySetupDraft()

    var body: some View {
        NavigationStack(path: $path) {
            CreateFirstHatchView { name in
                draft.name = name
                path.append(.scan)
            }
            .navigationDestination(for: Step.self) { step in
                destination(for: step)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func destination(for step: Step) -> some View {
        switch step {
        case .scan:
            ScanView(
                onScan: { path.append(.camera(UUID())) },
                onSkip: skipScanning
            )

        case .camera:
            CustomCameraView(
                onClose: pop,
                onCapture: { image, boundary in
                    draft.image = image
                    draft.boundary = boundary
                    draft.rectifiedImage = nil
                    draft.usesMockImage = false
                    path.append(.adjustBoundary)
                }
            )

        case .adjustBoundary:
            if let image = draft.image, let boundary = draft.boundary {
                HatcheryBoundaryAdjustmentView(
                    image: image,
                    boundary: boundary,
                    onRetake: pop,
                    onConfirm: { confirmedImage, confirmedBoundary in
                        draft.image = confirmedImage
                        draft.boundary = confirmedBoundary
                        draft.rectifiedImage = HatcheryImageProcessor.rectifiedImage(
                            from: confirmedImage,
                            boundary: confirmedBoundary
                        )
                        path.append(.dimensions)
                    }
                )
            }

        case .dimensions:
            if let image = draft.rectifiedImage ?? draft.image {
                HatcheryDimensionView(
                    hatchName: draft.name,
                    image: image,
                    usesMockImage: draft.usesMockImage,
                    initialDimension: draft.dimension,
                    onNext: { dimension in
                        guard let boundary = draft.boundary else { return }
                        guard let grid = HatcheryGridGenerator.generate(
                            dimension: dimension,
                            boundary: boundary
                        ) else { return }

                        draft.dimension = dimension
                        draft.grid = grid
                        path.append(.preview)
                    },
                    onRescan: restartCamera
                )
            }

        case .preview:
            if let image = draft.rectifiedImage ?? draft.image,
               let grid = draft.grid {
                HatcheryGridPreviewView(
                    hatchName: draft.name,
                    image: image,
                    usesMockImage: draft.usesMockImage,
                    dimension: draft.dimension,
                    grid: grid,
                    shape: .rectangle,
                    onDone: saveHatchery,
                    onBack: pop
                )
            }
        }
    }

    private func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func restartCamera() {
        path = [.scan, .camera(UUID())]
    }

    private func skipScanning() {
        let image = UIImage(named: "HatcherySamplePhoto") ?? UIImage()
        draft.image = image
        draft.rectifiedImage = image
        draft.usesMockImage = true
        draft.boundary = .fullImage
        path.append(.dimensions)
    }

    private func saveHatchery() {
        guard
            let photo = draft.image,
            let rectifiedPhoto = draft.rectifiedImage ?? draft.image,
            let boundary = draft.boundary,
            let grid = draft.grid
        else { return }

        let hatchery = Hatchery(
            id: UUID(),
            name: draft.name,
            shape: .rectangle,
            numberOfRow: grid.rows,
            numberOfColumn: grid.columns,
            lengthM: draft.dimension.heightM,
            widthM: draft.dimension.widthM,
            organizationId: nil
        )

        onSave(
            SavedHatchery(
                hatchery: hatchery,
                photo: photo,
                rectifiedPhoto: rectifiedPhoto,
                boundary: boundary,
                grid: grid
            )
        )
    }
}

#Preview {
    OnboardingFlowController(onSave: { _ in })
}
