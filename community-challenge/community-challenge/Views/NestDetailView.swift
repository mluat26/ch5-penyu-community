//
//  NestDetailView.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

struct NestDetailView: View {
    let nest: NestSample

    var body: some View {
        SheetChrome(title: nest.name) { sheetWidth in
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
                value: nest.temperature.celsiusText,
                unit: "°C",
                valueColor: Color.appGreenPrimary,
                alignment: .leading
            )
            .frame(width: 151, height: 85, alignment: .topLeading)

            sheetSummaryValue(title: "Eggs", value: nest.eggs.formatted())
                
            sheetSummaryValue(title: "Sections", value: nest.sectionID)
                
        }
        .frame(width: 370, height: 85, alignment: .top)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
    }
}

#Preview("Nest Detail", traits: .fixedLayout(width: 402, height: 874)) {
    NestDetailView(nest: .preview)
}
