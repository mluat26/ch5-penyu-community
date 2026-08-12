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
                let projectedCenter = sectionBoundary.point(columnFraction: 0.5, rowFraction: 0.5)
                sections.append(
                    HatcherySection(
                        id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                        row: row,
                        column: column,
                        widthM: targetSectionSizeM,
                        heightM: targetSectionSizeM,
                        boundary: sectionBoundary,
                        isActive: sandRegion?.contains(projectedCenter) ?? true
                    )
                )
            }
        }

        return HatcheryGrid(rows: rows, columns: columns, sections: sections)
    }
}
