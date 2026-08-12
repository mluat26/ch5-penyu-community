import SwiftUI

struct CreateFirstHatchView: View {

    @State private var hatchName: String = ""
    @FocusState private var isNameFocused: Bool

    var onCreate: (String) -> Void = { _ in }

    private var canContinue: Bool {
        !hatchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var body: some View {
        ZStack {

            // MARK: - Background

            Image("Onboarding1") // TODO: Change this later for using real gradient and image
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // MARK: - Content

            VStack(spacing: 0) {

                Spacer(minLength: 0)

                // MARK: - Header

                VStack(spacing: 12) {
                    Text("Create your first hatch")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appGreenPrimary)

                    Text("Name your first turtle egg incubator hatch")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 360)

                Spacer()

                // MARK: - Hatch Name Input

                VStack(spacing: 8) {

                    ZStack {

                        // Large typed text
                        TextField(
                            "",
                            text: $hatchName
                        )
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.appNeutralBlack)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit {
                            isNameFocused = false
                        }
                        .frame(height: 50)

                        // Small placeholder
                        if hatchName.isEmpty {
                            Text("Naming your hatch")
                                .foregroundStyle(Color.appNeutralGray1)
                                .allowsHitTesting(false)
                                .font(.body)
            
                        }
                    }

                    Rectangle()
                        .fill(Color.appNeutralGray3)
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()

                // MARK: - Create Button

                Button {
                    let trimmedName = hatchName
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    onCreate(trimmedName)
                } label: {
                    Text("Create a hatch")
                        .font(.headline)
                        .foregroundStyle(Color.appOffWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            Capsule()
                                .fill(Color.appGreenPrimary)
                                .opacity(canContinue ? 1.0 : 0.5)
                        )
                }
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }

        // MARK: - Keyboard Toolbar

        // Uncomment if you want a Done button above the keyboard.
        //
        // .toolbar {
        //     ToolbarItemGroup(placement: .keyboard) {
        //         Spacer()
        //
        //         Button("Done") {
        //             isNameFocused = false
        //         }
        //     }
        // }
    }
}

#Preview {
    CreateFirstHatchView()
}
