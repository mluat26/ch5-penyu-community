
//
//  HatchRecordedView.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 20/8/26.
//

import SwiftUI

struct HatchRecordedView: View {
    let nestNumber: String
    let successfulHatchCount: String
    let hatchingDate: String
    let incubationDays: String
    /// Optional because most nests have no logger. `%.0f` of a defaulted zero
    /// would render "0°C", which reads as a real measurement of a freezing
    /// nest rather than as no data.
    let averageTemperatureC: Double?
    let initialEggCount: String

    let onViewFullReport: () -> Void
    let onBackToHatchery: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(spacing: 12) {
                    // Same checkmark component as NestRegistrationSuccessView --
                    // handles the Lottie asset + Reduce Motion fallback already.
                    NestSuccessCheckmark(fallbackTint: .appGreenPrimary)

                    Text("Hatch recorded!")
                        .font(.title).bold()
                        .foregroundStyle(Color.appGreenPrimary)

                    Text("You can check full report now.")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1)
                }
                .padding(.top, 72)
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    HatchRecordedSummaryCard(
                        nestNumber: nestNumber,
                        successfulHatchCount: successfulHatchCount,
                        hatchingDate: hatchingDate,
                        incubationDays: incubationDays
                    )

                    HStack(spacing: 12) {
                        AddNestSummaryMetricCard(
                            title: "Average temperature",
                            value: averageTemperatureC.map { String(format: "%.0f°C", $0) } ?? "—°C"
                        )

                        AddNestSummaryMetricCard(
                            title: "Initial number of eggs",
                            value: initialEggCount
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                AddNestPrimaryButton(title: "View full report", action: onViewFullReport)
                AddNestPrimaryButton(
                    title: "Back to Hatchery",
                    action: onBackToHatchery,
                    isSecondary: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.white)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

/// New -- no existing component matches this exact 3-column layout
/// ("Succesful hatch / Hatching date / Incubation days" under a titled
/// card). `AddNestPreviewCard` is a different shape (nestNumber, eggCount,
/// hatchDate, daysLeft) so this is a sibling, not a replacement.
private struct HatchRecordedSummaryCard: View {
    let nestNumber: String
    let successfulHatchCount: String
    let hatchingDate: String
    let incubationDays: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nest #\(nestNumber)")
                    .font(.headline)
                    .foregroundStyle(.black)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 18)

            HStack(spacing: 0) {
                stat(value: successfulHatchCount, label: "Succesful\nhatch")
                divider
                stat(value: hatchingDate, label: "Hatching\ndate")
                divider
                stat(value: incubationDays, label: "Incubation\ndays")
            }
            .padding(.vertical, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#E0E0E0").opacity(0.29))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: "#EBEBEB"))
            .frame(width: 1, height: 44)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Hatch recorded", traits: .fixedLayout(width: 402, height: 874)) {
    HatchRecordedView(
        nestNumber: "055",
        successfulHatchCount: "50",
        hatchingDate: "Mar 01, 2026",
        incubationDays: "90",
        averageTemperatureC: 30,
        initialEggCount: "100",
        onViewFullReport: { },
        onBackToHatchery: { }
    )
}
