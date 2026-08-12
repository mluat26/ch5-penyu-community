import Foundation

struct Hatchery: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var shape: HatcheryShape
    var numberOfRows: Int
    var numberOfColumns: Int
    var lengthM: Double
    var widthM: Double
    var organizationID: UUID?

    var sectionCount: Int { numberOfRows * numberOfColumns }
    var areaM2: Double { lengthM * widthM }

    var cellSize: (width: Double, height: Double) {
        (
            widthM / Double(max(numberOfColumns, 1)),
            lengthM / Double(max(numberOfRows, 1))
        )
    }
}

struct CreateHatcheryInput: Hashable, Sendable {
    var name: String
    var shape: HatcheryShape
    var numberOfRows: Int
    var numberOfColumns: Int
    var lengthM: Double
    var widthM: Double
    var organizationID: UUID?
}

protocol HatcheryRepository: Sendable {
    func fetch(id: UUID) async throws -> Hatchery
    func create(_ input: CreateHatcheryInput) async throws -> Hatchery
}
