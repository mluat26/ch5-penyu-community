import SwiftUI

/// Presentation flow only: it maps typed SwiftUI routes to views. The actual
/// setup draft and creation workflow belong to `OnboardingController`.
struct OnboardingFlowView: View {
    @Bindable var controller: OnboardingController
    let onSave: (HatcherySessionData) -> Void

    @State private var router = OnboardingRouter()

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            CreateFirstHatchView { name in
                controller.setName(name)
                router.push(.scan)
            }
            .navigationDestination(for: OnboardingRoute.self) { route in
                destination(for: route, router: router)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func destination(
        for route: OnboardingRoute,
        router: OnboardingRouter
    ) -> some View {
        switch route {
        case .scan:
            ScanView(
                onScan: { router.push(.camera) },
                onSkip: {
                    controller.skipScanning()
                    router.push(.dimensions)
                }
            )

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
                        controller.confirmBoundary(
                            image: image,
                            boundary: boundary,
                            sandRegion: sandRegion
                        )
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
                    onDone: saveHatchery,
                    onBack: router.pop
                )
                .disabled(controller.isSaving)
            }
        }
    }

    private func saveHatchery() {
        Task {
            guard let hatchery = await controller.completeSetup() else { return }
            onSave(hatchery)
        }
    }
}

#Preview {
    OnboardingFlowView(
        controller: AppContainer().makeOnboardingController(),
        onSave: { _ in }
    )
}
