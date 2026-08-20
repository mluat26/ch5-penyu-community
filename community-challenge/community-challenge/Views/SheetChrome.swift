import SwiftUI

/// Shared sheet framing for hatchery dashboard details.
struct SheetChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: (CGFloat) -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let isReferenceWidth = abs(geometry.size.width - 402) < 0.5
            let pageInset = isReferenceWidth ? geometry.frame(in: .global).minX : 0
            let sheetWidth = geometry.size.width - (pageInset * 2)
            let contentScale = geometry.size.width / sheetWidth

            ZStack(alignment: .topLeading) {
                // Figma 199:3449 grounds the sheet in the grouped grey so the
                // white nest cards read as cards; on white they disappeared.
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                header(width: sheetWidth)
                    .frame(height: 54)
                    .offset(y: 11)

                content(sheetWidth)
            }
            .frame(width: sheetWidth, height: geometry.size.height, alignment: .topLeading)
            .scaleEffect(contentScale, anchor: .topLeading)
        }
    }

    private func header(width: CGFloat) -> some View {
        let horizontalInset = max((width - 358) / 2, 0)

        return ZStack {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.black)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(.white)
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: .circle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, horizontalInset)
            .accessibilityLabel("Close \(title)")
        

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .offset(y: 2)

            Image(systemName: "pencil")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.blue, in: Circle())
                .glassEffect(.regular, in: .circle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, horizontalInset)
                .accessibilityLabel("Edit \(title)")
                
        }
        .frame(width: width, height: 44, alignment: .top)
    }
}

func sheetSummaryValue(
    title: String,
    value: String,
    unit: String = "",
    valueColor: Color = .black,
    alignment: HorizontalAlignment = .center
) -> some View {
    let isTemperature = !unit.isEmpty

    return VStack(alignment: alignment, spacing: 4) {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(hex: "#8E8E93").opacity(0.75))
            .lineLimit(1)
            .padding(.leading, alignment == .leading ? 16 : 0)

        HStack(alignment: .top, spacing: 0) {
            Text(value)
                .font(.system(size: isTemperature ? 28 : 20, weight: isTemperature ? .bold : .semibold))
                .tracking(isTemperature ? 0.38 : 0)

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.top, 1)
            }
        }
        .foregroundStyle(valueColor)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: isTemperature ? 0 : 10)
    }
    .padding(.top, 16)
    .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: alignment == .leading ? .topLeading : .top
    )
}
