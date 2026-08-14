import SwiftUI
import UIKit

struct HatcheryGridPreviewView: View {
    let hatchName: String
    let image: UIImage
    let usesMockImage: Bool
    let dimension: HatcheryDimension
    let grid: HatcheryGrid
    let onDone: () -> Void
    let onBack: () -> Void
    /// Saving is the first thing in setup that can fail for a reason outside
    /// the app — no session, no network, a rejected write. Without showing it,
    /// Done appears to do nothing at all.
    var errorMessage: String?
    var isSaving = false

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(370, max(0, geometry.size.width - 32))

            ZStack(alignment: .top) {
                HatcherySetupBackdrop()

                VStack(spacing: 0) {
                    Spacer().frame(height: 102)

                    HatcherySetupHeader(
                        eyebrow: "Preview",
                        hatchName: hatchName
                    )

                    Spacer().frame(height: 40)

                    HatcheryGridDiagram(
                        image: image,
                        usesMockImage: usesMockImage,
                        grid: grid
                    )
                    .frame(width: contentWidth, height: 305)

                    Spacer().frame(height: 57)

                    summaryCards
                        .frame(
                            width: geometry.size.width,
                            height: 108,
                            alignment: .top
                        )

                    Spacer().frame(height: 32)

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

    private var summaryCards: some View {
        HStack(spacing: 10) {
            summaryCard(
                title: "Area",
                value: "\(dimension.areaM2.formatted(.number.precision(.fractionLength(0...1)))) m²"
            )
            summaryCard(title: "Sections", value: "\(grid.activeSectionCount)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(height: 20)

            Text(value)
                .font(.body)
                .fontWeight(.regular)
                .foregroundStyle(Color.appNeutralGray1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 22)
        }
        .padding(.top, 17)
        .frame(maxWidth: .infinity)
        .frame(height: 86, alignment: .top)
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
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.appRed)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
            }

            HatcherySetupButton(
                title: isSaving ? "Saving…" : "Done",
                isPrimary: true,
                action: onDone
            )
            HatcherySetupButton(title: "Back", isPrimary: false, action: onBack)
        }
    }

}

private struct HatcheryGridDiagram: View {
    let image: UIImage
    let usesMockImage: Bool
    let grid: HatcheryGrid

    private var rowCount: Int { max(grid.rows, 1) }
    private var columnCount: Int { max(grid.columns, 1) }

    var body: some View {
        GeometryReader { geometry in
            let imageWidth = max(0, geometry.size.width - 21)
            let innerWidth = max(0, imageWidth - 16)
            let columnGap = CGFloat(max(columnCount - 1, 0)) * 2
            let cellWidth = max(0, (innerWidth - columnGap) / CGFloat(columnCount))

            ZStack(alignment: .topLeading) {
                columnLabels(cellWidth: cellWidth)
                rowLabels

                HatcheryGridPhoto(
                    image: image,
                    usesMockImage: usesMockImage,
                    grid: grid
                )
                .frame(width: imageWidth, height: 279)
                .offset(x: 21, y: 26)
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

    private var rowLabels: some View {
        ForEach(0..<rowCount, id: \.self) { row in
            Text(row < grid.rowLabels.count ? grid.rowLabels[row] : "\(row + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 9, height: 16)
                .minimumScaleFactor(0.7)
                .position(x: 4.5, y: rowLabelCenter(for: row))
        }
    }

    private func rowLabelCenter(for row: Int) -> CGFloat {
        guard rowCount > 1 else { return 165.5 }
        return 74 + CGFloat(row) * (183 / CGFloat(rowCount - 1))
    }
}

private struct HatcheryGridPhoto: View {
    let image: UIImage
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

#Preview {
    let dimension = HatcheryDimension(widthM: 8, heightM: 6)
    let grid = HatcheryGridGenerator.generate(
        dimension: dimension,
        boundary: .fullImage
    )!

    HatcheryGridPreviewView(
        hatchName: "Hatch_01",
        image: UIImage(named: "HatcherySamplePhoto")!,
        usesMockImage: true,
        dimension: dimension,
        grid: grid,
        onDone: {},
        onBack: {}
    )
}
