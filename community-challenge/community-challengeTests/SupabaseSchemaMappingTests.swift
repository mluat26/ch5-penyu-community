import Foundation
import XCTest
@testable import community_challenge

final class SupabaseSchemaMappingTests: XCTestCase {
    func testHatcheryDTODecodesCurrentMisspelledColumn() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "number_of_row": 3,
              "number_of_collumn": 4,
              "name": "Hatch 01",
              "shape": "rectangle",
              "length_m": 6,
              "width_m": 8
            }
            """.utf8
        )

        let dto = try JSONDecoder().decode(HatcheryDTO.self, from: data)
        let hatchery = try dto.toEntity()

        XCTAssertEqual(hatchery.numberOfRows, 3)
        XCTAssertEqual(hatchery.numberOfColumns, 4)
    }

    func testHatcheryInsertUsesOnlyCurrentColumns() throws {
        let dto = try CreateHatcheryInput(
            name: "Hatch 01",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 6,
            widthM: 8,
            organizationID: nil
        ).toDTO()

        let object = try encodedObject(dto)

        XCTAssertEqual(object["number_of_row"] as? Int, 3)
        XCTAssertEqual(object["number_of_collumn"] as? Int, 4)
        XCTAssertNil(object["number_of_column"])
        XCTAssertNil(object["organization_id"])
    }

    func testHatcheryInsertRejectsUnbackedOrganizationID() {
        let input = CreateHatcheryInput(
            name: "Hatch 01",
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 4,
            lengthM: 6,
            widthM: 8,
            organizationID: UUID()
        )

        XCTAssertThrowsError(try input.toDTO())
    }

    func testNestDTOLeavesUnsupportedDomainFieldsUnset() throws {
        let hatcheryID = UUID()
        let dto = NestDTO(
            id: UUID(),
            numberOfEggs: 100,
            dateEggsLaid: nil,
            datePredictedHatch: nil,
            placeEggsLaid: nil,
            successEggsHatch: 90,
            hatcheryID: hatcheryID,
            placementRow: 1,
            placementColumn: 2,
            founderID: nil
        )

        let nest = try dto.toEntity()

        XCTAssertEqual(nest.hatcheryID, hatcheryID)
        XCTAssertNil(nest.datePredictedHatch)
        XCTAssertNil(nest.failEggsHatch)
    }

    func testNestInsertIncludesPredictedHatchColumn() {
        let predictedHatch = Date()
        let input = CreateNestInput(
            hatcheryID: UUID(),
            founderID: nil,
            numberOfEggs: 100,
            dateEggsLaid: nil,
            datePredictedHatch: predictedHatch,
            placeEggsLaid: nil,
            placementRow: 1,
            placementColumn: 2
        )

        XCTAssertEqual(input.toDTO().datePredictedHatch, predictedHatch)
    }

    func testIoTDataDTODecodesCurrentTemperatureColumn() throws {
        let id = UUID()
        let nestID = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "nest_id": "\(nestID.uuidString)",
              "sensor_id": null,
              "temperature": 29.5,
              "alert": "low"
            }
            """.utf8
        )

        let dto = try JSONDecoder().decode(IoTDataDTO.self, from: data)

        XCTAssertEqual(dto.nestID, nestID)
        XCTAssertEqual(dto.temperature, 29.5)
    }

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
