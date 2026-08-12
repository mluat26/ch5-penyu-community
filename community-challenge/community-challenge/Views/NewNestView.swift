//
//  NewNestView.swift
//  community-challenge
//

import SwiftUI

struct AddNestScanView: View {
    let onScanned: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Image("AddNestScanBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("Scan QR on your\nsmart nest")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(hex: "#2B2B2B"))

                    Text("This will connect the nest\nto your hatchery.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(hex: "#4A4A4A"))
                }
                .frame(width: 282, height: 104, alignment: .top)
                .offset(x: -5, y: 12)

                Button(action: onScanned) {
                    ZStack {
                        Image("AddNestScannerPhoto")
                            .resizable()
                            .scaledToFill()
                            .opacity(0.30)

                        Image(systemName: "viewfinder")
                            .font(.system(size: 350, weight: .thin))
                            .foregroundStyle(Color(hex: "#2E7D5B"))
                            .offset(y: -25)
                            .accessibilityHidden(true)

                        Image(systemName: "qrcode")
                            .font(.system(size: 150, weight: .regular))
                            .foregroundStyle(Color(hex: "#2E7D5B"))
                            .offset(y: -23)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 370, height: 376)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan sample QR code")
                .padding(.top, 10)
                .offset(x: -3)

                Button(action: onManualEntry) {
                    Text("Can’t scan? Enter code manually")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: "#2E7D5B"))
                        .frame(width: 324, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Uses the sample bucket code 00000000")
                .padding(.top, 10)
                .offset(x: -5)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 122)

            AddNestNavigationHeader()
                .padding(.top, 72)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct NewNestView: View {
    let controller: NestController
    let onReview: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#FDF6EE")
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Text("Nest Info")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .tracking(-0.43)
                        .foregroundStyle(Color(hex: "#2B2B2B"))
                        .frame(width: 350, height: 42, alignment: .leading)

                    VStack(spacing: 10) {
                        fieldGroup(
                            label: "QR / Bucket ID",
                            value: controller.draft.bucketID,
                            fieldHeight: 42,
                            subdued: true
                        )

                        fieldGroup(
                            label: "Nest Number",
                            value: controller.draft.nestNumber,
                            fieldHeight: 42,
                            subdued: true
                        )

                        fieldGroup(
                            label: "Section",
                            value: controller.draft.section,
                            fieldHeight: 44,
                            trailingSymbol: "chevron.down"
                        )
                    }
                    .padding(.top, 20)

                    VStack(spacing: 10) {
                        fieldGroup(
                            label: "Number of eggs",
                            value: controller.draft.numberOfEggs,
                            fieldHeight: 44
                        )

                        fieldGroup(
                            label: "Egg collection date",
                            value: controller.draft.collectionDate,
                            fieldHeight: 50,
                            trailingSymbol: "calendar"
                        )

                        fieldGroup(
                            label: "Egg inspection date",
                            value: controller.draft.inspectionDate,
                            fieldHeight: 50,
                            trailingSymbol: "calendar"
                        )

                        fieldGroup(
                            label: "Estimated hatch date",
                            value: controller.draft.hatchDate,
                            fieldHeight: 50,
                            trailingSymbol: "calendar"
                        )
                    }
                    .padding(.top, 29)

                    Button(action: onReview) {
                        Text("Review")
                            .font(.body)
                            .fontWeight(.semibold)
                            .tracking(-0.43)
                            .foregroundStyle(Color(hex: "#FAF8F4"))
                            .frame(width: 365, height: 55)
                    }
                    .buttonStyle(.plain)
                    .background(Color(hex: "#2E7D5B"), in: RoundedRectangle(cornerRadius: 26))
                    .padding(.top, 30)
                    .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 122)
            }
            .scrollIndicators(.hidden)

            AddNestNavigationHeader()
                .padding(.top, 72)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func fieldGroup(
        label: String,
        value: String,
        fieldHeight: CGFloat,
        subdued: Bool = false,
        trailingSymbol: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .tracking(-0.23)
                .foregroundStyle(Color(hex: "#575757"))
                .frame(height: 20, alignment: .leading)

            HStack(spacing: 10) {
                Text(value)
                    .font(subdued ? .subheadline : .body)
                    .tracking(subdued ? -0.23 : -0.43)
                    .foregroundStyle(.black)

                Spacer(minLength: 0)

                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: trailingSymbol == "calendar" ? 17 : 16, weight: .regular))
                        .foregroundStyle(Color(hex: "#575757"))
                        .frame(width: 27, height: 28)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 350, height: fieldHeight)
            .background(fieldBackground(subdued: subdued), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if subdued {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "#FFFBF7"), lineWidth: 1)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(width: 350, height: fieldHeight + 50, alignment: .top)
    }

    private func fieldBackground(subdued: Bool) -> Color {
        subdued ? Color(hex: "#787878").opacity(0.20) : .white
    }
}

struct ReviewNewNestView: View {
    let controller: NestController
    let onSave: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Image("AddNestReviewBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            reviewCard
                .padding(.top, 122)
                .offset(x: -4)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Button(action: onSave) {
                    Text("Save Nest")
                        .font(.body)
                        .fontWeight(.semibold)
                        .tracking(-0.43)
                        .foregroundStyle(Color(hex: "#FAF8F4"))
                        .frame(width: 365, height: 55)
                }
                .buttonStyle(.plain)
                .background(Color(hex: "#2E7D5B"), in: RoundedRectangle(cornerRadius: 26))
                .disabled(controller.isSaving)
                .padding(.bottom, 65)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: -4)

            AddNestNavigationHeader()
                .padding(.top, 72)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var reviewCard: some View {
        VStack(spacing: 11) {
            HStack(alignment: .top, spacing: 35) {
                Image("AddNestCube")
                    .resizable()
                    .frame(width: 53.5, height: 75)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Nest #\(controller.draft.nestNumber)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .tracking(-0.43)
                        .foregroundStyle(Color(hex: "#2B2B2B"))

                    Text(controller.draft.section)
                        .font(.body)
                        .tracking(-0.43)
                        .foregroundStyle(Color(hex: "#4A4A4A"))
                }
                .padding(.top, 10)

                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
            .padding(.top, 26)
            .frame(width: 350, height: 127, alignment: .topLeading)

            VStack(spacing: 0) {
                reviewRow(label: "Number of eggs", value: controller.draft.numberOfEggs, height: 75, drawsDivider: true)
                reviewRow(label: "Egg collection date", value: "Jan 01, 2026", height: 62, drawsDivider: true)
                reviewRow(label: "Egg inspection date", value: "Feb 01,2026", height: 62, drawsDivider: true)
                reviewRow(label: "Estimated hatch date", value: "Mar 01,2026", height: 77, drawsDivider: false)
            }
            .frame(width: 340, height: 276)
        }
        .padding(.top, 10)
        .frame(width: 350, height: 423, alignment: .top)
        .background(Color(hex: "#FFFBF7"), in: RoundedRectangle(cornerRadius: 26))
    }

    private func reviewRow(label: String, value: String, height: CGFloat, drawsDivider: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Color(hex: "#575757"))

            Spacer(minLength: 0)

            Text(value)
                .font(.callout)
                .foregroundStyle(Color(hex: "#575757"))
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .overlay(alignment: .bottom) {
            if drawsDivider {
                Rectangle()
                    .fill(Color(hex: "#C6C6C8"))
                    .frame(width: 300, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct AddNestNavigationHeader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: "#2B2B2B"))
                    .frame(width: 40, height: 40, alignment: .leading)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            Text("Add New Nest")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: "#2B2B2B"))
                .offset(x: -7)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
    }
}

#Preview("Scan QR", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack {
        AddNestScanView(onScanned: { }, onManualEntry: { })
    }
}

#Preview("Nest info", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack {
        NewNestView(controller: PreviewNestController.make(), onReview: { })
    }
}

#Preview("Review nest", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack {
        ReviewNewNestView(controller: PreviewNestController.make(), onSave: { })
    }
}

@MainActor
private enum PreviewNestController {
    static func make() -> NestController {
        NestController(
            hatcheryID: UUID(),
            nestService: NestService(repository: InMemoryNestRepository())
        )
    }
}
