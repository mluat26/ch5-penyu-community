import SwiftUI

struct OnboardingFlowController: View {

    /// Steps that come after the root "create hatch" screen.
    private enum Step: Hashable {
        case scan
        case camera
    }

    @State private var path: [Step] = []
    @State private var hatchName: String = ""

    /// Result of the camera step (consumed by Phases 4–5).
    @State private var capturedImage: UIImage?
    @State private var capturedQuad: QuadPoints?

    var body: some View {
        NavigationStack(path: $path) {

            // MARK: - Root: Name the hatch

            CreateFirstHatchView { name in
                hatchName = name
                path.append(.scan)
            }
            .navigationDestination(for: Step.self) { step in
                switch step {

                // MARK: - Scan hatchery area

                case .scan:
                    ScanView(
                        onScan: { path.append(.camera) },
                        onSkip: { /* TODO: real skip target once the post-scan flow exists */ }
                    )
                    .navigationBarBackButtonHidden(false)

                // MARK: - Camera (Phase 1)

                case .camera:
                    CustomCameraView(
                        onClose: { if !path.isEmpty { path.removeLast() } },
                        onConfirm: { image, quad in
                            // Phase 4 converts (image, quad) into a normalized
                            // HatcheryBoundary; Phase 5 navigates to Dimension.
                            capturedImage = image
                            capturedQuad = quad
                        }
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}

#Preview {
    OnboardingFlowController()
}
