import Foundation

nonisolated enum HatcheryGridGenerator {
    static let targetSectionSizeM = 2.0

    static func generate(
        dimension: HatcheryDimension,
        boundary: HatcheryBoundary,
        sandRegion: HatcherySandRegion? = nil
    ) -> HatcheryGrid? {
        guard dimension.isValid, boundary.isValid, sandRegion?.isValid ?? true else { return nil }

        let columns = Int(floor(dimension.widthM / targetSectionSizeM))
        let rows = Int(floor(dimension.heightM / targetSectionSizeM))
        guard columns > 0, rows > 0 else { return nil }

        // The sand polygon is edited in the original photo's coordinate
        // space. Perspective correction, however, creates the rectangular
        // image that the grid is drawn on. Classify each logical cell in that
        // same corrected space so its active state agrees with the visible
        // segmented image rather than a similar-but-not-identical bilinear
        // projection.
        let rectifiedSandRegion: HatcherySandRegion?
        if let sandRegion {
            guard
                let mapper = HatcheryPerspectiveMapper(boundary: boundary),
                let mappedRegion = mapper.rectifiedRegion(for: sandRegion)
            else {
                return nil
            }
            rectifiedSandRegion = mappedRegion
        } else {
            rectifiedSandRegion = nil
        }

        var sections: [HatcherySection] = []
        sections.reserveCapacity(rows * columns)

        for row in 0..<rows {
            for column in 0..<columns {
                let sectionBoundary = boundary.sectionBoundary(
                    row: row,
                    column: column,
                    rowCount: rows,
                    columnCount: columns
                )
                let rectifiedCenter = NormalizedPoint(
                    x: (Double(column) + 0.5) / Double(columns),
                    y: (Double(row) + 0.5) / Double(rows)
                )
                sections.append(
                    HatcherySection(
                        id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                        row: row,
                        column: column,
                        widthM: targetSectionSizeM,
                        heightM: targetSectionSizeM,
                        boundary: sectionBoundary,
                        isActive: rectifiedSandRegion?.contains(rectifiedCenter) ?? true
                    )
                )
            }
        }

        return HatcheryGrid(rows: rows, columns: columns, sections: sections)
    }
}
