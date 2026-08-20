
//
//  HatchedForm1.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 20/8/26.
//

import SwiftUI

struct HatchedForm1: View {
    @Bindable var controller: HatchingController
    let onNext: () -> Void
    /// Explicit rather than `@Environment(\.dismiss)`: this screen is shown in
    /// a cover presented from inside a sheet, where `dismiss` is ambiguous
    /// about which of the two it means. The Add Nest flow uses callbacks for
    /// the same reason.
    let onCancel: () -> Void

    /// The only genuinely local state left. Everything a person types belongs
    /// to the controller, so the review screen reads the same numbers.
    @State private var showDatePicker = false

    private let accentGreen = Color(red: 0.29, green: 0.45, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hatchling details")
                        .font(.title).bold()
                        .foregroundColor(accentGreen)
                    Text("Enter the hatching results")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 48, height: 48)
                }
                .modifier(GlassCloseButtonModifier())
            }
            .padding(.horizontal)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Total eggs
                    sectionLabel("Total eggs")
                    Text("\(controller.nest.numberOfEggs)")
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(.systemGray6))
                        )

                    // Actual hatching date
                    sectionLabel("Actual hatching date")
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            Text("Hatching date")
                                .foregroundColor(.black)
                            Spacer()
                            Text(controller.hatchedOnOrdinalText)
                                .foregroundColor(.gray)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.systemGray3))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color(.systemGray4).opacity(0.4), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showDatePicker) {
                        VStack {
                            DatePicker("Hatching date", selection: $controller.draft.hatchedOn, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .padding()
                            Button("Done") { showDatePicker = false }
                                .padding(.bottom)
                        }
                        .presentationDetents([.medium])
                    }

                    // Hatching result
                    sectionLabel("Hatching result")
                    VStack(spacing: 0) {
                        resultRow(title: "Rotten eggs", text: $controller.draft.rottenEggs)
                        Divider()
                        resultRow(title: "Unhatched eggs", text: $controller.draft.unhatchedEggs)
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Hatched eggs")
                                    .foregroundColor(.black)
                                Text("Auto-calculate (adjust if needed)")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray3))
                            }
                            Spacer()
                            TextField("", text: Binding(
                                get: {
                                    controller.draft.hatchedEggs.isEmpty
                                        ? "\(controller.suggestedHatchedCount)"
                                        : controller.draft.hatchedEggs
                                },
                                set: { controller.draft.hatchedEggs = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.blue)
                            .frame(width: 70)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(.systemGray4).opacity(0.4), lineWidth: 1)
                    )

                    if controller.exceedsClutch {
                        Text("That totals \(controller.totalAccountedFor) eggs, but the nest holds \(controller.nest.numberOfEggs).")
                            .font(.footnote)
                            .foregroundColor(Color(hex: "#FF383C"))
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 24)
            }

            // Next button
            Button {
                onNext()
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(controller.canSubmit ? accentGreen : Color(.systemGray3))
                    )
            }
            .disabled(!controller.canSubmit)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).bold()
            .foregroundColor(accentGreen)
    }

    @ViewBuilder
    private func resultRow(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.black)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.blue)
                .frame(width: 70)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}


private struct GlassCloseButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }
}

#Preview {
    HatchedForm1(
        controller: HatchingPreviewFixtures.controller(),
        onNext: {},
        onCancel: {}
    )
}
