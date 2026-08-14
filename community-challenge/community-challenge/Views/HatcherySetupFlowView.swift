import SwiftUI

/// The route at which a hatchery setup run begins. First and additional
/// hatcheries begin with their Figma name-entry screens; re-scanning begins at
/// the same scan screen but saves through the backend's update path.
enum HatcherySetupEntryPoint {
    case firstHatch
    case additionalHatch
    case rescan
}

/// Presentation flow only: it maps typed SwiftUI routes to views. The actual
/// setup draft and creation workflow belong to `HatcherySetupController`.
struct HatcherySetupFlowView: View {
    @Bindable var controller: HatcherySetupController
    let onSave: (HatcherySessionState) -> Void
    let entryPoint: HatcherySetupEntryPoint
    let onCancel: () -> Void

    @State private var router = HatcherySetupRouter()

    init(
        controller: HatcherySetupController,
        onSave: @escaping (HatcherySessionState) -> Void,
        entryPoint: HatcherySetupEntryPoint = .firstHatch,
        onCancel: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onSave = onSave
        self.entryPoint = entryPoint
        self.onCancel = onCancel
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            rootView(router: router)
            .navigationDestination(for: HatcherySetupRoute.self) { route in
                destination(for: route, router: router)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func rootView(router: HatcherySetupRouter) -> some View {
        switch entryPoint {
        case .firstHatch:
            CreateFirstHatchView { name in
                controller.setName(name)
                router.push(.scan)
            }

        case .additionalHatch:
            CreateFirstHatchView(
                style: .additionalHatch,
                onCreate: { name in
                    controller.setName(name)
                    router.push(.scan)
                },
                onBack: onCancel
            )

        case .rescan:
            scanView(router: router)
        }
    }

    @ViewBuilder
    private func destination(
        for route: HatcherySetupRoute,
        router: HatcherySetupRouter
    ) -> some View {
        switch route {
        case .scan:
            scanView(router: router)

        case .camera:
            CustomCameraView(
                onClose: router.pop,
                onCapture: { image, boundary in
                    controller.storeCapturedImage(image, boundary: boundary)
                    router.push(.adjustBoundary)
                }
            )

        case .adjustBoundary:
            if let image = controller.draft.image,
               let boundary = controller.draft.boundary {
                HatcheryBoundaryAdjustmentView(
                    image: image,
                    boundary: boundary,
                    sandRegion: controller.draft.sandRegion,
                    onRetake: {
                        controller.discardCaptureState()
                        router.pop()
                    },
                    onConfirm: { image, boundary, sandRegion in
                        guard await controller.confirmBoundary(
                            image: image,
                            boundary: boundary,
                            sandRegion: sandRegion
                        ) else { return }
                        router.push(.dimensions)
                    }
                )
            }

        case .dimensions:
            if let image = controller.draft.rectifiedImage ?? controller.draft.image,
               let boundary = controller.draft.boundary {
                HatcheryDimensionView(
                    hatchName: controller.draft.name,
                    image: image,
                    boundary: boundary,
                    usesMockImage: controller.draft.usesMockImage,
                    showsCapturedImage: !controller.draft.isAwaitingScan,
                    initialDimension: controller.draft.dimension,
                    onNext: { dimension in
                        if controller.generateGrid(for: dimension) {
                            router.push(.preview)
                        }
                    },
                    onRescan: {
                        controller.discardCaptureState()
                        router.restartCamera()
                    }
                )
            }

        case .preview:
            if let image = controller.draft.rectifiedImage ?? controller.draft.image,
               let grid = controller.draft.grid {
                HatcheryGridPreviewView(
                    hatchName: controller.draft.name,
                    image: image,
                    usesMockImage: controller.draft.usesMockImage,
                    dimension: controller.draft.dimension,
                    grid: grid,
                    isSaving: controller.isSaving,
                    errorMessage: controller.errorMessage,
                    onDone: saveHatchery,
                    onBack: router.pop
                )
                .disabled(controller.isSaving)
            }
        }
    }

    private func scanView(router: HatcherySetupRouter) -> some View {
        ScanView(
            onScan: { router.push(.camera) },
            onSkip: {
                controller.skipScanning()
                router.push(.dimensions)
            },
            onCancel: entryPoint == .rescan ? onCancel : nil
        )
    }

    private func saveHatchery() {
        Task {
            guard let hatchery = await controller.completeSetup() else { return }
            onSave(hatchery)
        }
    }
}

#Preview {
    HatcherySetupFlowView(
        controller: AppContainer().makeHatcherySetupController(),
        onSave: { _ in }
    )
}
