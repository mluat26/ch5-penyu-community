import SwiftUI

struct HatcheryScanInstructionBanner: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 40)

            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 366, height: 76)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
    }
}

struct HatcheryScanSideControl: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HatcheryScanSideLabel(systemName: systemName, label: label)
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
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 337)

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
