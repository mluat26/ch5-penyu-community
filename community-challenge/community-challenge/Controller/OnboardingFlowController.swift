import SwiftUI

struct OnboardingFlowController: View {

    /// A photo plus the boundary drawn on it.
    ///
    /// Equality and hashing use `id` alone. `UIImage` inherits `NSObject`
    /// equality, which compares pixel data, and SwiftUI diffs the navigation
    /// path on every update — hashing multi-megapixel photos there would be
    /// wasteful. A fresh `id` per capture also gives each pushed screen its own
    /// identity, so `@State` seeded from these values never survives a retake.
    private struct Shot: Hashable {
        let id = UUID()
        let image: UIImage
        let boundary: HatcheryBoundary
        let usesMockImage: Bool

        static func == (lhs: Shot, rhs: Shot) -> Bool { lhs.id == rhs.id }

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// A sized-and-gridded hatchery, ready to preview or save.
    private struct Layout: Hashable {
        let id = UUID()
        let shot: Shot
        let rectifiedImage: UIImage
        let dimension: HatcheryDimension
        let grid: HatcheryGrid

        static func == (lhs: Layout, rhs: Layout) -> Bool { lhs.id == rhs.id }

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Every step carries what it needs to render.
    ///
    /// These screens used to read their photo and boundary from a separate
    /// `@State` draft that was mutated in the same tick as the push. When
    /// SwiftUI built the destination before that mutation became visible, the
    /// `if let` guards fell through and the step rendered as a blank page with
    /// nothing but a back button. Payload carried in the path cannot fall out
    /// of step with the path.
    private enum Step: Hashable {
        case scan
        case camera(UUID)
        case adjustBoundary(Shot)
        case dimensions(Shot)
        case preview(Layout)
    }

    let onSave: (SavedHatchery) -> Void

    @State private var path: [Step] = []
    @State private var hatchName = ""
    @State private var dimension = HatcheryDimension(widthM: 15, heightM: 7)

    var body: some View {
        NavigationStack(path: $path) {
            CreateFirstHatchView { name in
                hatchName = name
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
                    path.append(
                        .adjustBoundary(
                            Shot(
                                image: image,
                                boundary: boundary,
                                usesMockImage: false
                            )
                        )
                    )
                }
            )

        case .adjustBoundary(let shot):
            HatcheryBoundaryAdjustmentView(
                image: shot.image,
                boundary: shot.boundary,
                onRetake: pop,
                onConfirm: { confirmedImage, confirmedBoundary in
                    path.append(
                        .dimensions(
                            Shot(
                                image: confirmedImage,
                                boundary: confirmedBoundary,
                                usesMockImage: false
                            )
                        )
                    )
                }
            )

        case .dimensions(let shot):
            HatcheryDimensionView(
                hatchName: hatchName,
                image: shot.image,
                boundary: shot.boundary,
                usesMockImage: shot.usesMockImage,
                initialDimension: dimension,
                onNext: { entered in advance(shot: shot, dimension: entered) },
                onRescan: restartCamera
            )

        case .preview(let layout):
            HatcheryGridPreviewView(
                hatchName: hatchName,
                image: layout.rectifiedImage,
                usesMockImage: layout.shot.usesMockImage,
                dimension: layout.dimension,
                grid: layout.grid,
                shape: .rectangle,
                onDone: { saveHatchery(layout) },
                onBack: pop
            )
        }
    }

    private func advance(shot: Shot, dimension entered: HatcheryDimension) {
        // Falling back keeps Next from doing nothing at all if the confirmed
        // boundary is somehow unusable; the user can still re-scan for a
        // better one.
        let boundary = shot.boundary.isValid ? shot.boundary : .fullImage

        guard let grid = HatcheryGridGenerator.generate(
            dimension: entered,
            boundary: boundary
        ) else { return }

        dimension = entered
        path.append(
            .preview(
                Layout(
                    shot: shot,
                    rectifiedImage: HatcheryImageProcessor.rectifiedImage(
                        from: shot.image,
                        boundary: boundary
                    ),
                    dimension: entered,
                    grid: grid
                )
            )
        )
    }

    private func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func restartCamera() {
        path = [.scan, .camera(UUID())]
    }

    private func skipScanning() {
        path.append(
            .dimensions(
                Shot(
                    image: UIImage(named: "HatcherySamplePhoto") ?? UIImage(),
                    boundary: .fullImage,
                    usesMockImage: true
                )
            )
        )
    }

    private func saveHatchery(_ layout: Layout) {
        let hatchery = Hatchery(
            id: UUID(),
            name: hatchName,
            shape: .rectangle,
            numberOfRow: layout.grid.rows,
            numberOfColumn: layout.grid.columns,
            lengthM: layout.dimension.heightM,
            widthM: layout.dimension.widthM,
            organizationId: nil
        )

        onSave(
            SavedHatchery(
                hatchery: hatchery,
                photo: layout.shot.image,
                rectifiedPhoto: layout.rectifiedImage,
                boundary: layout.shot.boundary,
                grid: layout.grid
            )
        )
    }
}

#Preview {
    OnboardingFlowController(onSave: { _ in })
}
