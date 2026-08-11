import SwiftUI

struct ScanView: View {

    var onScan: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        ZStack {

            // MARK: - Background

            Image("Onboarding2") // TODO : Change this later for using real gradient and image
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // MARK: - Content

            VStack(spacing: 0) {

                Spacer(minLength: 0)

                // MARK: - Header

                VStack(spacing: 12) {
                    Text("Scan your\nhatchery area")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appGreenPrimary)

                    Text("This step makes it easier for you to find\nthe turtle nest.")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 320 )

                Spacer()

                // MARK: - Actions

                VStack(spacing: 8) {

                    // MARK: Scan Button

                    Button {
                        onScan()
                    } label: {
                        Text("Scan now")
                            .font(.headline)
                            .foregroundStyle(Color.appOffWhite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                Capsule()
                                    .fill(Color.appGreenPrimary)
                            )
                    }
                    .padding(.horizontal, 24)

                    // MARK: Skip Button

                    Button {
                        onSkip()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundStyle(Color.appNeutralGray1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .padding(.bottom, 56)
            }
        }
    }
}

#Preview {
    ScanView()
}
