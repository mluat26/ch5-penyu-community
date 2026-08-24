import SwiftUI
import UIKit

struct HatcheryDimensionView: View {
    let hatchName: String
    let image: UIImage
    let sandRegion: HatcherySandRegion?
    let usesMockImage: Bool
    let showsCapturedImage: Bool
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
        sandRegion: HatcherySandRegion?,
        usesMockImage: Bool,
        showsCapturedImage: Bool = true,
        initialDimension: HatcheryDimension,
        onNext: @escaping (HatcheryDimension) -> Void,
        onRescan: @escaping () -> Void
    ) {
        self.hatchName = hatchName
        self.image = image
        self.sandRegion = sandRegion
        self.usesMockImage = usesMockImage
        self.showsCapturedImage = showsCapturedImage
        self.onNext = onNext
        self.onRescan = onRescan
        // `.grouping(.never)`: this seeds a text field that `number(from:)` reads
        // back, and it cannot parse a thousands separator.
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .grouping(.never)
        _widthText = State(initialValue: initialDimension.widthM.formatted(style))
        _heightText = State(initialValue: initialDimension.heightM.formatted(style))
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(370, max(0, geometry.size.width - 32))
            // A focused field is the reliable, immediate signal for this
            // screen's compact keyboard layout. It avoids tying the Figma
            // state to a particular keyboard height or device orientation.
            let isEditingDimension = focusedField != nil
            let photoHeight: CGFloat = isEditingDimension ? 95 : 279
            let headerToPhotoSpacing: CGFloat = isEditingDimension ? 40 : 42
            let photoToFormSpacing: CGFloat = isEditingDimension ? 40 : 38

            ZStack(alignment: .top) {
                HatcherySetupBackdrop()

                VStack(spacing: 0) {
                    Spacer().frame(height: 102)

                    HatcherySetupHeader(
                        eyebrow: "Dimension setting",
                        hatchName: hatchName
                    )

                    // 402 × 874 Figma reference: the photo is anchored at
                    // y=210 after the 66 pt header that begins at y=102.
                    Spacer().frame(height: headerToPhotoSpacing)

                    photo
                        // The keyboard Figma state keeps the image's width
                        // and crop rules intact; only its visible canvas gets
                        // shorter. No additional scale effect or altered
                        // aspect mode is applied to the image.
                        .frame(
                            width: photoBoxWidth(
                                forHeight: photoHeight,
                                maximum: contentWidth
                            ),
                            height: photoHeight
                        )

                    Spacer().frame(height: photoToFormSpacing)

                    dimensionForm
                        .frame(width: contentWidth, height: 137)
                        // The Figma form is centred 6 pt to the right of the
                        // screen centre; keeping that reference alignment is
                        // visually important against the photo above.
                        .offset(x: 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Keep the CTA stack at its reference y-position. When the
                // keyboard opens, iOS naturally covers it while the compact
                // photo and dimension fields remain visible above the keys.
                actionButtons
                    .frame(width: contentWidth, height: 122)
                    .offset(y: 710)
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
            .animation(.easeInOut(duration: 0.25), value: isEditingDimension)
        }
        // Keep the reference canvas behind the status/home areas while still
        // allowing SwiftUI's keyboard-safe layout to shrink and reflow.
        .ignoresSafeArea(.container)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    /// The photo card's width: the image's own aspect ratio at the fixed card
    /// height, never wider than the content width.
    ///
    /// The height stays fixed so the dimension form below never moves. The card
    /// narrows instead, which is what removes the white plate either side of a
    /// tall scan. `rectification` crops the corrected photo to the sand
    /// region's bounding box, so a tall narrow sand area genuinely produces a
    /// tall narrow photo -- `scaledToFill` used to hide that by cropping it
    /// back to a wide box, which is what read as a zoom.
    ///
    /// The skipped-scan grid keeps the full width: it draws section geometry
    /// rather than a photo, so it has no aspect ratio to respect.
    private func photoBoxWidth(forHeight height: CGFloat, maximum: CGFloat) -> CGFloat {
        guard showsCapturedImage else { return maximum }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return maximum }
        return min(maximum, height * size.width / size.height)
    }

    private var photo: some View {
        ZStack {
            Color.white

            if showsCapturedImage {
                // Fitted, not filled. `scaledToFill` cropped the photo to
                // cover this box, which reads as an unexplained zoom whenever
                // the photo's shape does not match it -- and there is nothing
                // to gain by hiding part of the scan on the screen that asks
                // you to describe it.
                HatcherySetupImage(
                    image: image,
                    usesMockCrop: usesMockImage,
                    contentMode: .fit
                )

                // Same mode as the photo. A fitted photo under a fill-mode
                // mapper would draw the sand outline somewhere the sand is not.
                HatcherySandRegionOverlay(
                    region: .constant(sandRegion),
                    imageSize: image.size,
                    isEditable: false,
                    contentMode: .fit
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            } else if let skippedScanGrid {
                // Skipping a camera scan should not leave the hatchery area
                // visually empty. Show the same section geometry that Next
                // will save, but deliberately omit every image layer.
                HatcherySkippedScanGrid(
                    rows: skippedScanGrid.rows,
                    columns: skippedScanGrid.columns
                )
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityLabel(
            showsCapturedImage
                ? "Captured hatchery area"
                : "Hatchery grid without a scan image"
        )
    }

    /// The skipped-scan state still has a valid full-image boundary. Build a
    /// lightweight visual preview from the dimensions currently in the form;
    /// the persisted grid is still generated only when the user taps Next.
    private var skippedScanGrid: HatcheryGrid? {
        guard let enteredDimension else { return nil }
        return HatcheryGridGenerator.generate(
            dimension: enteredDimension,
            boundary: .fullImage,
            sandRegion: sandRegion
        )
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
                Text(validationMessage ?? "Input your hatching demesion")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(validationMessage == nil ? Color.appNeutralGray1 : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(height: 22)
            }
            .multilineTextAlignment(.center)
            .frame(height: 51)

            Spacer().frame(height: 16)

            HStack(spacing: 36) {
                dimensionField(
                    label: "W",
                    labelWidth: 20,
                    fieldWidth: 128,
                    textWidth: 64,
                    unitSpacing: 6,
                    text: $widthText,
                    field: .width
                )

                dimensionField(
                    label: "H",
                    labelWidth: 16,
                    fieldWidth: 116,
                    textWidth: 64,
                    unitSpacing: 6,
                    text: $heightText,
                    field: .height
                )
            }
            .frame(height: 70)
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

            HStack(spacing: unitSpacing) {
                TextField("0", text: text)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.black)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: field)
                    .multilineTextAlignment(.center)
                    .frame(width: textWidth, height: 41)
                    .lineLimit(1)

                Text("m")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.black.opacity(0.5))
                    .frame(height: 25)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: fieldWidth, height: 70)
            .background(HatcherySetupPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HatcherySetupPalette.border, lineWidth: 1)
            }
        }
        .frame(height: 70)
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
}

/// A photo-free grid for the "Skip for now" dimension screen. `Canvas` keeps
/// the live preview smooth even for a large, valid hatchery grid.
private struct HatcherySkippedScanGrid: View {
    let rows: Int
    let columns: Int

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let horizontalGaps = CGFloat(max(columns - 1, 0)) * gap
            let verticalGaps = CGFloat(max(rows - 1, 0)) * gap
            let cellWidth = max(0, (size.width - horizontalGaps) / CGFloat(max(columns, 1)))
            let cellHeight = max(0, (size.height - verticalGaps) / CGFloat(max(rows, 1)))
            let cellColor = HatcherySetupPalette.gridOverlay.opacity(0.34)

            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(
                        x: CGFloat(column) * (cellWidth + gap),
                        y: CGFloat(row) * (cellHeight + gap),
                        width: cellWidth,
                        height: cellHeight
                    )
                    context.fill(Path(rect), with: .color(cellColor))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }
}

#Preview("Figma reference", traits: .fixedLayout(width: 402, height: 874)) {
    HatcheryDimensionView(
        hatchName: "Hatch 01",
        image: UIImage(named: "HatcherySamplePhoto") ?? UIImage(),
        sandRegion: .default(from: .fullImage),
        usesMockImage: true,
        initialDimension: HatcheryDimension(widthM: 4, heightM: 5),
        onNext: { _ in },
        onRescan: {}
    )
}

#Preview("Skipped scan", traits: .fixedLayout(width: 402, height: 874)) {
    HatcheryDimensionView(
        hatchName: "Hatch 01",
        image: UIImage(),
        sandRegion: .default(from: .fullImage),
        usesMockImage: false,
        showsCapturedImage: false,
        initialDimension: HatcheryDimension(widthM: 4, heightM: 5),
        onNext: { _ in },
        onRescan: {}
    )
}
