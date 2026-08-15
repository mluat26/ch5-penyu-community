//
//  NestDetailView.swift
//  community-challenge
//

import SwiftUI

struct NestDetailView: View {
    let item: NestDashboardItem
    let ordinal: Int
    let sectionID: String

    var body: some View {
        SheetChrome(
            title: "Nest #\(item.nest.displayNumber(fallbackOrdinal: ordinal))"
        ) { sheetWidth in
            Image("NestImage")
                .resizable()
                .scaledToFill()
                .frame(width: 320, height: 207)
                .offset(x: (sheetWidth - 327) / 2, y: 70)
                .accessibilityHidden(true)

            summary
                .offset(x: (sheetWidth - 370) / 2, y: 277)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            sheetSummaryValue(
                title: "Average temperature",
                value: temperatureText(item.latestTemperatureC),
                unit: "°C",
                valueColor: Color.appGreenPrimary,
                alignment: .leading
            )
            .frame(width: 151, height: 85, alignment: .topLeading)

            sheetSummaryValue(title: "Eggs", value: item.nest.numberOfEggs.formatted())

            sheetSummaryValue(title: "Section", value: sectionID)
        }
        .frame(width: 370, height: 85, alignment: .top)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
    }

    private func temperatureText(_ temperature: Double?) -> String {
        guard let temperature else { return "—" }
        return temperature.formatted(.number.precision(.fractionLength(1)))
    }
}
