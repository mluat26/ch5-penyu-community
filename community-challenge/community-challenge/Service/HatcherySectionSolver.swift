import Foundation

/// Picks the rows x columns configuration whose actual section dimensions
/// land closest to a square 4 m² ideal, instead of forcing fixed 2 m sections
/// and truncating away whatever doesn't divide evenly.
nonisolated enum HatcherySectionSolver {
    static let targetSectionAreaM2 = 4.0
    static let areaErrorWeight = 2.0
    static let shapeErrorWeight = 1.0

    struct HatcherySectionLayout: Equatable {
        let rows: Int
        let columns: Int
        let sectionWidthM: Double
        let sectionLengthM: Double

        var totalSections: Int { rows * columns }
        var sectionAreaM2: Double { sectionWidthM * sectionLengthM }
    }

    /// - Parameters:
    ///   - maxRowsOrColumns: reuses `HatcheryGridSnapshot.maximumRowsOrColumns`.
    ///   - maxCellCount: reuses `HatcheryGridSnapshot.maximumCellCount`.
    // ponytail: brute-forces every rows x columns pair in the bound (~10k
    // checks at the default 100x100 cap) instead of enumerating divisors of
    // the target area. Fine at this size; switch to a divisor-based search
    // if the bounds ever grow past a few hundred.
    static func solve(
        dimension: HatcheryDimension,
        maxRowsOrColumns: Int = HatcheryGridSnapshot.maximumRowsOrColumns,
        maxCellCount: Int = HatcheryGridSnapshot.maximumCellCount
    ) -> HatcherySectionLayout? {
        let widthM = dimension.widthM
        let heightM = dimension.heightM
        guard widthM.isFinite, heightM.isFinite, widthM > 0, heightM > 0 else { return nil }

        // Tie-break key: lowest score, then fewest sections, then most columns.
        var best: HatcherySectionLayout?
        var bestKey: (score: Double, sectionCount: Int, negColumns: Int)?
        let epsilon = 1e-9

        for columns in 1...maxRowsOrColumns {
            for rows in 1...maxRowsOrColumns {
                guard columns * rows <= maxCellCount else { continue }

                let sectionWidth = widthM / Double(columns)
                let sectionLength = heightM / Double(rows)
                let areaError = abs(sectionWidth * sectionLength - targetSectionAreaM2)
                let shapeError = max(sectionWidth, sectionLength) / min(sectionWidth, sectionLength) - 1.0
                let score = areaErrorWeight * areaError + shapeErrorWeight * shapeError
                let key = (score: score, sectionCount: columns * rows, negColumns: -columns)

                if let current = bestKey, !isBetter(key, than: current, epsilon: epsilon) {
                    continue
                }

                best = HatcherySectionLayout(
                    rows: rows,
                    columns: columns,
                    sectionWidthM: sectionWidth,
                    sectionLengthM: sectionLength
                )
                bestKey = key
            }
        }

        return best
    }

    private static func isBetter(
        _ key: (score: Double, sectionCount: Int, negColumns: Int),
        than other: (score: Double, sectionCount: Int, negColumns: Int),
        epsilon: Double
    ) -> Bool {
        if abs(key.score - other.score) > epsilon { return key.score < other.score }
        if key.sectionCount != other.sectionCount { return key.sectionCount < other.sectionCount }
        return key.negColumns < other.negColumns
    }
}
