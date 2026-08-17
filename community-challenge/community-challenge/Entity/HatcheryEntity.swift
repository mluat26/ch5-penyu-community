import Foundation

enum HatcheryShape: String, CaseIterable, Identifiable, Sendable {
    case square
    case rectangle
    case circle

    var id: String { rawValue }
}

struct HatcheryEntity: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var shape: HatcheryShape
    var numberOfRows: Int
    var numberOfColumns: Int
    var lengthM: Double
    var widthM: Double
    var organizationID: UUID?
    /// Nil only for legacy hatcheries created before the backend retained this
    /// audit timestamp. New rows receive it from Postgres at insertion.
    var createdAt: Date? = nil

    var sectionCount: Int { numberOfRows * numberOfColumns }
    var areaM2: Double { lengthM * widthM }

    var cellSize: (width: Double, height: Double) {
        (
            widthM / Double(max(numberOfColumns, 1)),
            lengthM / Double(max(numberOfRows, 1))
        )
    }
}
