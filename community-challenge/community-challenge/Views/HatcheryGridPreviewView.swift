import SwiftUI
import UIKit

struct HatcheryGridPreviewView: View {
    let hatchName: String
    let image: UIImage
    let sandRegion: HatcherySandRegion?
    let usesMockImage: Bool
    let dimension: HatcheryDimension
    let grid: HatcheryGrid
    /// Saving is the first thing in setup that can fail for a reason outside
    /// the app — no session, no network, a rejected write. Without showing it,
    /// Done appears to do nothing at all.
    let isSaving: Bool
    let errorMessage: String?
    let onDone: () -> Void
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(370, max(0, geometry.size.width - 32))

            ZStack(alignment: .top) {
                HatcheryGridPreviewBackdrop()

                VStack(spacing: 0) {
                    Spacer().frame(height: 102)

                    HatcheryGridPreviewHeader(hatchName: hatchName)

                    // Figma reference: the grid labels start at y=184 and the
                    // image grid starts at y=210 on the 402 × 874 canvas.
                    Spacer().frame(height: 16)

                    HatcheryGridDiagram(
                        image: image,
                        sandRegion: sandRegion,
                        usesMockImage: usesMockImage,
                        grid: grid
                    )
                    .frame(
                        width: contentWidth,
                        height: HatcheryGridDiagram.height(
                            forContentWidth: contentWidth,
                            image: image
                        )
                    )

                    Spacer().frame(height: 33)

                    sectionsOverview
                        .frame(width: contentWidth, height: 159)

                    Spacer().frame(height: 29)

                    actionButtons
                        .frame(width: contentWidth, height: 122)

                    Spacer(minLength: 42)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sectionsOverview: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Sections overview")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.45)
                    .foregroundStyle(.black)
                    .frame(height: 25)

                Text("Here is your section overview")
                    .font(.system(size: 17, weight: .regular))
                    .tracking(-0.43)
                    .foregroundStyle(Color.appNeutralGray1)
                    .frame(height: 22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 51)

            HStack(spacing: 10) {
                summaryCard(
                    title: "Area",
                    value: "\(dimension.areaM2.formatted(.number.precision(.fractionLength(0...1)))) m²"
                )
                summaryCard(title: "Sections", value: "\(grid.activeSectionCount)")
            }
            .frame(height: 92)
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.23)
                .foregroundStyle(Color(hex: "#2A2A2A"))
                .frame(height: 20)

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .tracking(0.38)
                .foregroundStyle(Color.appNeutralGray1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(HatcherySetupPalette.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(HatcherySetupPalette.border, lineWidth: 1)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HatcherySetupButton(
                title: isSaving ? "Saving…" : "Done",
                isPrimary: true,
                action: onDone
            )
            .disabled(isSaving)

            HatcherySetupButton(title: "Back", isPrimary: false, action: onBack)
                .disabled(isSaving)
        }
        .overlay(alignment: .top) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appRed)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .offset(y: -32)
                    .accessibilityLabel("Unable to save: \(errorMessage)")
            }
        }
    }
}

private struct HatcheryGridPreviewBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white

                // Reuse the same Figma ellipse as the other hatchery screens
                // so preview does not drift in color, size, or blur strength.
                HatcheryWarmEllipse(fill: HatcherySetupPalette.warmGlow)
                    .position(
                        x: (geometry.size.width - 1) / 2,
                        y: -67.5
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HatcheryGridPreviewHeader: View {
    let hatchName: String

    var body: some View {
        VStack(spacing: 0) {
            Text("Preview")
                .font(.system(size: 20, weight: .regular))
                .tracking(-0.45)
                .foregroundStyle(Color(uiColor: .systemGray))
                .frame(height: 25)

            Text(hatchName)
                .font(.system(size: 34, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.appGreenPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 41)
        }
        .multilineTextAlignment(.center)
        .frame(width: 321, height: 66)
    }
}

private struct HatcheryGridDiagram: View {
    let image: UIImage
    let sandRegion: HatcherySandRegion?
    let usesMockImage: Bool
    let grid: HatcheryGrid

    private var rowCount: Int { max(grid.rows, 1) }
    private var columnCount: Int { max(grid.columns, 1) }

    /// Gap above the photo, left for the column labels.
    static let photoTopOffset: CGFloat = 26

    /// The photo's drawn height for a given content width.
    ///
    /// Derived from the image rather than fixed at 279: `rectification` crops
    /// the corrected photo to the sand region's bounding box, so a hardcoded
    /// height let `scaledToFill` crop the sand off again for any sand shape
    /// that was not 349:279, and the cell grid no longer matched the photo.
    static func photoHeight(forContentWidth width: CGFloat, image: UIImage) -> CGFloat {
        let imageWidth = max(0, width - 21)
        guard image.size.width > 0, image.size.height > 0 else { return 279 }
        return imageWidth * image.size.height / image.size.width
    }

    /// What the caller must reserve: the label gap plus the photo.
    static func height(forContentWidth width: CGFloat, image: UIImage) -> CGFloat {
        photoTopOffset + photoHeight(forContentWidth: width, image: image)
    }

    var body: some View {
        GeometryReader { geometry in
            let imageWidth = max(0, geometry.size.width - 21)
            let innerWidth = max(0, imageWidth - 16)
            let columnGap = CGFloat(max(columnCount - 1, 0)) * 2
            let cellWidth = max(0, (innerWidth - columnGap) / CGFloat(columnCount))

            let photoHeight = Self.photoHeight(
                forContentWidth: geometry.size.width,
                image: image
            )

            ZStack(alignment: .topLeading) {
                columnLabels(cellWidth: cellWidth)
                rowLabels(photoHeight: photoHeight)

                HatcheryGridPhoto(
                    image: image,
                    sandRegion: sandRegion,
                    usesMockImage: usesMockImage,
                    grid: grid
                )
                .frame(width: imageWidth, height: photoHeight)
                .offset(x: 21, y: Self.photoTopOffset)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hatchery grid, \(grid.columns) columns and \(grid.rows) rows")
    }

    private func columnLabels(cellWidth: CGFloat) -> some View {
        ForEach(0..<columnCount, id: \.self) { column in
            Text(column < grid.columnLabels.count
                 ? grid.columnLabels[column]
                 : HatcheryGrid.columnLabel(column))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.5))
                .frame(height: 16)
                .position(
                    x: 29 + cellWidth / 2 + CGFloat(column) * (cellWidth + 2),
                    y: 8
                )
        }
    }

    private func rowLabels(photoHeight: CGFloat) -> some View {
        ForEach(0..<rowCount, id: \.self) { row in
            Text(row < grid.rowLabels.count ? grid.rowLabels[row] : "\(row + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 9, height: 16)
                .minimumScaleFactor(0.7)
                .position(x: 4.5, y: rowLabelCenter(for: row, photoHeight: photoHeight))
        }
    }

    /// Mirrors `HatcheryGridPhoto`'s own row layout (photo offset y=26, 8 pt
    /// content padding, 2 pt row spacing) so labels land on the real cell
    /// centers for any row count, not just the 3-row mock this was originally
    /// tuned against. `photoHeight` is passed in rather than hardcoded so it
    /// cannot drift from the height the photo is actually drawn at.
    private func rowLabelCenter(for row: Int, photoHeight: CGFloat) -> CGFloat {
        let photoTop = Self.photoTopOffset
        let contentPadding: CGFloat = 8
        let rowSpacing: CGFloat = 2

        let innerHeight = max(0, photoHeight - contentPadding * 2)
        let rowGaps = CGFloat(max(rowCount - 1, 0)) * rowSpacing
        let cellHeight = max(0, (innerHeight - rowGaps) / CGFloat(rowCount))
        let rowTop = photoTop + contentPadding + CGFloat(row) * (cellHeight + rowSpacing)

        return rowTop + cellHeight / 2
    }
}

private struct HatcheryGridPhoto: View {
    let image: UIImage
    let sandRegion: HatcherySandRegion?
    let usesMockImage: Bool
    let grid: HatcheryGrid

    private var rows: Int { max(grid.rows, 1) }
    private var columns: Int { max(grid.columns, 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HatcherySetupImage(
                    image: image,
                    usesMockCrop: usesMockImage
                )

                HatcherySandRegionOverlay(
                    region: .constant(sandRegion),
                    imageSize: image.size,
                    isEditable: false
                )

                let horizontalGaps = CGFloat(max(columns - 1, 0)) * 2
                let verticalGaps = CGFloat(max(rows - 1, 0)) * 2
                let innerWidth = max(0, geometry.size.width - 16)
                let innerHeight = max(0, geometry.size.height - 16)
                let cellWidth = max(0, (innerWidth - horizontalGaps) / CGFloat(columns))
                let cellHeight = max(0, (innerHeight - verticalGaps) / CGFloat(rows))

                VStack(spacing: 2) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<columns, id: \.self) { column in
                                let isActive = grid.isSectionActive(row: row, column: column)

                                Rectangle()
                                    .fill(
                                        isActive
                                            ? HatcherySetupPalette.gridOverlay.opacity(0.34)
                                            : Color.black.opacity(0.14)
                                    )
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
                .frame(width: innerWidth, height: innerHeight)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview("Figma reference", traits: .fixedLayout(width: 402, height: 874)) {
    let dimension = HatcheryDimension(widthM: 4, heightM: 5)
    let grid = HatcheryGrid(
        rows: 3,
        columns: 4,
        sections: (0..<3).flatMap { row in
            (0..<4).map { column in
                HatcherySection(
                    id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                    row: row,
                    column: column,
                    widthM: 2,
                    heightM: 2,
                    boundary: .fullImage.sectionBoundary(
                        row: row,
                        column: column,
                        rowCount: 3,
                        columnCount: 4
                    )
                )
            }
        }
    )

    HatcheryGridPreviewView(
        hatchName: "Hatch 01",
        image: UIImage(named: "HatcherySamplePhoto")!,
        sandRegion: .default(from: .fullImage),
        usesMockImage: true,
        dimension: dimension,
        grid: grid,
        isSaving: false,
        errorMessage: nil,
        onDone: {},
        onBack: {}
    )
}
