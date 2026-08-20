import SwiftUI

struct ScanView: View {

    let onScan: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let xOffset = (geometry.size.width - 402) / 2

            ZStack(alignment: .topLeading) {
                Color.white

                Image("Onboarding2")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 402, height: 874)
                    .clipped()
                    .offset(x: xOffset)
                    .allowsHitTesting(false)

                HatcherySetupBackButton(action: onBack)
                    .offset(x: xOffset + 16, y: 87)

                VStack(spacing: 12) {
                    Text("Scan your\nhatchery area")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.appGreenPrimary)
                        .frame(height: 82)

                    Text("This step makes it easier for you to find the turtle nest.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appNeutralGray1)
                        .frame(height: 44)
                }
                .multilineTextAlignment(.center)
                .frame(width: 321, height: 138)
                .offset(x: xOffset + 41, y: 158)

                VStack(spacing: 16) {
                    HatcheryPrimaryButton(title: "Scan now", action: onScan)
                        .frame(width: 370, height: 55)

                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(.system(size: 13))
                            .tracking(-0.08)
                            .foregroundStyle(Color.appNeutralGray1.opacity(0.5))
                            .frame(width: 370, height: 18)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 370, height: 89, alignment: .top)
                .offset(x: xOffset + 16, y: 742)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ScanView(onScan: {}, onSkip: {}, onBack: {})
}
