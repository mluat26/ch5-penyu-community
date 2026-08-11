import SwiftUI

struct CreateFirstHatchView: View {

    @State private var hatchName: String = ""
    @FocusState private var isNameFocused: Bool

    let onCreate: (String) -> Void

    private var canContinue: Bool {
        !hatchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let xOffset = (geometry.size.width - 402) / 2

            ZStack(alignment: .topLeading) {
                Color.white

                Image("Onboarding1")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 402, height: 874)
                    .clipped()
                    .offset(x: xOffset)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Text("Create your first\nhatch")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.appGreenPrimary)
                        .frame(height: 82)

                    Text("Name your first turtle egg incubator\nhatch")
                        .font(.system(size: 17))
                        .tracking(0)
                        .foregroundStyle(Color.appNeutralGray1)
                        .frame(height: 44)
                }
                .multilineTextAlignment(.center)
                .frame(width: 287, height: 138)
                .offset(x: xOffset + 58, y: 423)

                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "#E6E6E6"))
                        .frame(width: 271, height: 1)

                    TextField("Naming your hatch", text: $hatchName)
                        .font(.system(size: 17))
                        .tracking(0)
                        .foregroundStyle(Color.appNeutralBlack)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit { isNameFocused = false }
                        .frame(width: 303, height: 42)
                        .offset(y: 7)
                }
                .frame(width: 303, height: 52)
                .offset(x: xOffset + 50, y: 631)

                Button {
                    guard canContinue else {
                        isNameFocused = true
                        return
                    }
                    onCreate(hatchName.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Text("Create a hatch")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FAF8F4"))
                        .frame(width: 370, height: 55)
                        .background(
                            Color.appGreenPrimary,
                            in: RoundedRectangle(cornerRadius: 26)
                        )
                }
                .buttonStyle(.plain)
                .offset(x: xOffset + 16, y: 742)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

#Preview {
    CreateFirstHatchView(onCreate: { _ in })
}
