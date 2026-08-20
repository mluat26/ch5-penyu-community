//
//  ReviewHatchlingsDetailsView.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 20/8/26.
//

import SwiftUI

// AddNestPreviewDetailRow is already defined elsewhere in the project — reused as-is below.

// MARK: - New component: card-style summary row (top block, no icons)


struct NestSummaryCard: View {
    struct Stat: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    let title: String
    let stats: [Stat]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
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
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    if index > 0 { divider }
                    VStack(spacing: 6) {
                        Text(stat.value)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(stat.label)
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#8E8E93"))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#8E8E93").opacity(0.08))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: "#EBEBEB"))
            .frame(width: 1, height: 44)
    }
}

// MARK: - Screen

struct ReviewHatchlingsDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    // Replace with real draft/controller values when wiring up
    let nestID: String = "Nest #055"
    let successfulHatch: Int = 50
    let hatchingDate: String = "Mar 01, 2026"
    let incubationDays: Int = 90
    let rottenEggs: Int = 12
    let unhatchedEggs: Int = 123
    let hatchingPercent: Double = 26.3

    private let accentGreen = Color(red: 0.29, green: 0.45, blue: 0.34)

    var onSave: () -> Void = {}
    var onEdit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review\nhatchlings details")
                        .font(.title).bold()
                        .foregroundColor(accentGreen)
                    Text("Please review the details before saving.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                }
                Spacer()
                Button(action: { dismiss() }) {
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
                VStack(spacing: 24) {
                    NestSummaryCard(
                        title: nestID,
                        stats: [
                            .init(value: "\(successfulHatch)", label: "Succesful\nhatch"),
                            .init(value: hatchingDate, label: "Hatching\ndate"),
                            .init(value: "\(incubationDays)", label: "Incubation\ndays"),
                        ]
                    )

                    AddNestPreviewDetailRow(items: [
                        .init(
                            systemImage: "viewfinder.trianglebadge.exclamationmark",
                            label: "Rotten eggs",
                            value: "\(rottenEggs)"
                        ),
                        .init(
                            systemImage: "clock.badge.exclamationmark",
                            label: "Unhatched eggs",
                            value: "\(unhatchedEggs)"
                        ),
                        .init(
                            systemImage: "checkmark.seal",
                            label: "Hatching %",
                            value: String(format: "%.1f%%", hatchingPercent)
                        ),
                    ])
                }
                .padding(.horizontal)
                .padding(.top, 24)

                Spacer(minLength: 40)
            }

            // Save + Edit
            VStack(spacing: 14) {
                Button(action: onSave) {
                    Text("Save")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 28).fill(accentGreen))
                }

                Button(action: onEdit) {
                    Text("Edit details")
                        .font(.subheadline).bold()
                        .foregroundColor(accentGreen)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
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
    ReviewHatchlingsDetailsView()
}
