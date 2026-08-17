import SwiftUI

struct HatcheryScanInstructionBanner: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.largeTitle)
                .foregroundStyle(.white)

            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                // Let the label grow to as many lines as it needs; the chip
                // sizes to the text rather than the text being squeezed into a
                // fixed 76 pt box with no optical margin.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 366)
        .glassEffect(in: RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, 20)
    }
}

struct HatcheryScanSideControl: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HatcheryScanSideLabel(systemName: systemName, label: label)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 78)
    }
}

struct HatcheryScanSideLabel: View {
    let systemName: String
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .glassEffect()
                .frame(width: 72, height: 48)

            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
        .frame(width: 72, height: 78)
    }
}

struct HatcheryScanPrimaryControl: View {
    var systemName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .overlay {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                    }
                    .frame(width: 107, height: 107)

                Circle()
                    .fill(.white)
                    .frame(width: 87, height: 87)

                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.appGreenPrimary)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 107, height: 107)
    }
}

struct HatcheryScanGradients: View {
    let bottomHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // The top scrim is deliberately short and semi-transparent: it
                // sits behind the instruction banner, and liquid glass needs
                // varied content to refract. Over a full-black field the
                // material has nothing to lens and flattens into a plain
                // frosted rectangle.
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)

                LinearGradient(
                    colors: [.black.opacity(0), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bottomHeight)
                .offset(y: max(geometry.size.height - bottomHeight, 0))
            }
        }
        .allowsHitTesting(false)
    }
}
