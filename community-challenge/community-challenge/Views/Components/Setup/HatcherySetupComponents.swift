import SwiftUI
import UIKit

enum HatcherySetupPalette {
    static let warmGlow = HatcheryWarmEllipse.figmaFill
    static let surface = Color(hex: "#F1F1F1")
    static let border = Color(hex: "#EBEBEB")
    static let gridOverlay = Color(hex: "#003C22")
}

struct HatcherySetupBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.white

                HatcheryWarmEllipse(fill: HatcherySetupPalette.warmGlow)
                    .position(x: (geometry.size.width - 1) / 2, y: -67.5)
            }
        }
        .allowsHitTesting(false)
    }
}

struct HatcherySetupImage: View {
    let image: UIImage
    let usesMockCrop: Bool

    var body: some View {
        GeometryReader { geometry in
            if usesMockCrop {
                // Figma's mock photo uses a fixed zoom and offset.
                Image(uiImage: image)
                    .resizable()
                    .frame(
                        width: geometry.size.width * 1.5821,
                        height: geometry.size.height * 1.6213
                    )
                    .offset(
                        x: -geometry.size.width * 0.2767,
                        y: -geometry.size.height * 0.4283
                    )
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .clipped()
    }
}

/// Draws a confirmed boundary over an aspect-filled photo, read-only.
///
/// Mirrors `HatcheryOverlay`'s fill and stroke so the area the user adjusted
/// during scanning is recognisable on the screens that follow. Assumes the
/// photo is rendered with `scaledToFill`, matching `HatcherySetupImage`'s
/// non-mock path.
struct HatcheryBoundaryOverlay: View {
    let imageSize: CGSize
    let boundary: HatcheryBoundary
    var color: Color = .appGreenPrimary

    var body: some View {
        GeometryReader { geometry in
            let mapper = AspectFillImageMapper(
                imageSize: imageSize,
                containerSize: geometry.size
            )
            let quad = mapper.viewQuad(for: boundary)

            ZStack {
                path(for: quad).fill(color.opacity(0.30))
                path(for: quad).stroke(color, lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func path(for quad: QuadPoints) -> Path {
        var path = Path()
        path.move(to: quad.topLeft)
        path.addLine(to: quad.topRight)
        path.addLine(to: quad.bottomRight)
        path.addLine(to: quad.bottomLeft)
        path.closeSubpath()
        return path
    }
}

struct HatcherySetupHeader: View {
    let eyebrow: String
    let hatchName: String

    var body: some View {
        VStack(spacing: 0) {
            Text(eyebrow)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(uiColor: .systemGray))
                .frame(height: 25)

            Text(hatchName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.appGreenPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 41)
        }
        .multilineTextAlignment(.center)
        .frame(width: 321, height: 66)
    }
}

struct HatcherySetupButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: HatcheryDesignMetrics.primaryButtonCornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        if isPrimary {
            HatcheryPrimaryButton(title: title, action: action)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemGray6), in: shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .frame(height: HatcheryDesignMetrics.primaryButtonHeight)
        }
    }
}
