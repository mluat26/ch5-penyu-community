import SwiftUI

struct ScanView: View {

    let onScan: () -> Void
    let onSkip: () -> Void
    let onCancel: (() -> Void)?

    init(
        onScan: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onScan = onScan
        self.onSkip = onSkip
        self.onCancel = onCancel
    }

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

                if let onCancel {
                    Button(action: onCancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.appGreenPrimary)
                        .frame(width: 84, height: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .offset(x: xOffset + 16, y: 87)
                    .accessibilityLabel("Back")
                }

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
                    Button(action: onScan) {
                        Text("Scan now")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "#FAF8F4"))
                            .frame(width: 370, height: 55)
                            .background(
                                Color.appGreenPrimary,
                                in: RoundedRectangle(cornerRadius: 26)
                            )
                    }
                    .buttonStyle(.plain)

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
    ScanView(onScan: {}, onSkip: {})
}
