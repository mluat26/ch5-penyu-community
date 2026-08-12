import SwiftUI
import UIKit

struct HatcheryDimensionView: View {
    let hatchName: String
    let image: UIImage
    let boundary: HatcheryBoundary
    let usesMockImage: Bool
    let onNext: (HatcheryDimension) -> Void
    let onRescan: () -> Void

    @State private var widthText: String
    @State private var heightText: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case width
        case height
    }

    init(
        hatchName: String,
        image: UIImage,
        boundary: HatcheryBoundary,
        usesMockImage: Bool,
        initialDimension: HatcheryDimension,
        onNext: @escaping (HatcheryDimension) -> Void,
        onRescan: @escaping () -> Void
    ) {
        self.hatchName = hatchName
        self.image = image
        self.boundary = boundary
        self.usesMockImage = usesMockImage
        self.onNext = onNext
        self.onRescan = onRescan
        _widthText = State(initialValue: Self.inputText(for: initialDimension.widthM))
        _heightText = State(initialValue: Self.inputText(for: initialDimension.heightM))
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(370, max(0, geometry.size.width - 32))

            ZStack(alignment: .top) {
                HatcherySetupBackdrop()

                VStack(spacing: 0) {
                    Spacer().frame(height: 102)

                    HatcherySetupHeader(
                        eyebrow: "Dimension setting",
                        hatchName: hatchName
                    )

                    Spacer().frame(height: 61)

                    photo
                        .frame(width: contentWidth, height: 279)

                    Spacer().frame(height: 31)

                    dimensionForm
                        .frame(width: min(321, contentWidth), height: 141)

                    Spacer().frame(height: 30)

                    actionButtons
                        .frame(width: contentWidth, height: 122)

                    Spacer(minLength: 42)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // The layout deliberately ignores the keyboard region, so the
            // decimal pad sits on top of Next. It has no return key, hence the
            // explicit ways out below.
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var photo: some View {
        ZStack {
            HatcherySetupImage(
                image: image,
                usesMockCrop: usesMockImage
            )

            HatcheryBoundaryOverlay(
                imageSize: image.size,
                boundary: boundary
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityLabel("Captured hatchery area")
    }

    private var dimensionForm: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Dimension")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(height: 25)

                // Doubles as the validation slot so an unusable value explains
                // itself in place, without disturbing the fixed layout.
                Text(validationMessage ?? "Input your hatching dimension")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(validationMessage == nil ? Color.appNeutralGray1 : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 22)
            }
            .multilineTextAlignment(.center)
            .frame(height: 51)

            Spacer().frame(height: 27)

            HStack(spacing: 45) {
                dimensionField(
                    label: "W",
                    labelWidth: 20,
                    fieldWidth: 88,
                    textWidth: 43,
                    unitSpacing: 1,
                    text: $widthText,
                    field: .width
                )

                dimensionField(
                    label: "H",
                    labelWidth: 16,
                    fieldWidth: 98,
                    textWidth: 48,
                    unitSpacing: 6,
                    text: $heightText,
                    field: .height
                )
            }
            .frame(height: 63)
        }
    }

    private func dimensionField(
        label: String,
        labelWidth: CGFloat,
        fieldWidth: CGFloat,
        textWidth: CGFloat,
        unitSpacing: CGFloat,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack(spacing: 13) {
            Text(label)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: labelWidth, height: 25)

            HStack(alignment: .top, spacing: unitSpacing) {
                TextField("0", text: text)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.black)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: field)
                    .frame(width: textWidth, height: 41, alignment: .topLeading)
                    .lineLimit(1)

                Text("m")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.black.opacity(0.5))
                    .frame(width: 18, height: 25, alignment: .top)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(width: fieldWidth, height: 63, alignment: .topLeading)
            .background(HatcherySetupPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HatcherySetupPalette.border, lineWidth: 1)
            }
        }
        .frame(height: 63)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HatcherySetupButton(title: "Next", isPrimary: true) {
                guard let enteredDimension else { return }
                focusedField = nil
                onNext(enteredDimension)
            }
            .disabled(enteredDimension == nil)
            .opacity(enteredDimension == nil ? 0.5 : 1)

            HatcherySetupButton(title: "Re-scanning", isPrimary: false) {
                focusedField = nil
                onRescan()
            }
        }
    }

    private var enteredDimension: HatcheryDimension? {
        guard
            let width = Self.number(from: widthText),
            let height = Self.number(from: heightText)
        else {
            return nil
        }

        let dimension = HatcheryDimension(widthM: width, heightM: height)
        return dimension.isValid ? dimension : nil
    }

    private var validationMessage: String? {
        guard
            let width = Self.number(from: widthText),
            let height = Self.number(from: heightText)
        else {
            return "Enter a width and a height in metres."
        }

        return HatcheryDimension(widthM: width, heightM: height).validationMessage
    }

    private static func number(from text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "."))
    }

    private static func inputText(for value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum HatcherySetupPalette {
    static let warmGlow = Color(hex: "#FEF6ED")
    static let buttonForeground = Color(hex: "#FAF8F4")
    static let surface = Color(hex: "#F1F1F1")
    static let border = Color(hex: "#EBEBEB")
    static let gridOverlay = Color(hex: "#003C22")
}

struct HatcherySetupBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.white

                Circle()
                    .fill(HatcherySetupPalette.warmGlow)
                    .frame(width: 621, height: 621)
                    .blur(radius: 100)
                    .position(x: geometry.size.width / 2, y: -67.5)
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
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            // The pill has to be drawn *inside* the label, and the content
            // shape stated explicitly. With `.plain`, a bare Text only accepts
            // taps on its glyphs, and a background applied outside the Button
            // is decoration the hit test never sees — which left most of this
            // 370 pt-wide button dead.
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isPrimary ? HatcherySetupPalette.buttonForeground : .black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isPrimary ? Color.appGreenPrimary : Color(uiColor: .systemGray6))
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(height: 55)
    }
}

#Preview {
    HatcheryDimensionView(
        hatchName: "Hatch_01",
        image: UIImage(named: "HatcherySamplePhoto") ?? UIImage(),
        boundary: .defaultSuggestion,
        usesMockImage: false,
        initialDimension: HatcheryDimension(widthM: 15, heightM: 7),
        onNext: { _ in },
        onRescan: {}
    )
}
