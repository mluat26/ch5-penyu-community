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
        XCTAssertNil(hatchery.createdAt)
    }

    func testHatcheryDTOMapsCreatedAt() throws {
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
              "width_m": 8,
              "created_at": "2026-06-15T00:00:00Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let hatchery = try decoder.decode(HatcheryDTO.self, from: data).toEntity()

        XCTAssertEqual(hatchery.createdAt, Date(timeIntervalSince1970: 1_781_481_600))
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

    func testNestDTOMapsHatchCountsAndInspectionDate() throws {
        let hatcheryID = UUID()
        let nextInspection = Date()
        let dto = NestDTO(
            id: UUID(),
            numberOfEggs: 100,
            dateEggsLaid: nil,
            datePredictedHatch: nil,
            bucketID: nil,
            nestNumber: nil,
            latitude: nil,
            longitude: nil,
            locationAddress: nil,
            successEggsHatch: 90,
            failEggsHatch: 10,
            eggsUnhatched: 5,
            hatcheryID: hatcheryID,
            placementRow: 1,
            placementColumn: 2,
            founderID: nil,
            nextInspectionDate: nextInspection,
            createdAt: nil
        )

        let nest = try dto.toEntity()

        XCTAssertEqual(nest.hatcheryID, hatcheryID)
        XCTAssertNil(nest.datePredictedHatch)
        // fail_eggs_hatch and next_inspection_date now exist in the schema, so
        // neither is dropped in mapping any more.
        XCTAssertEqual(nest.successEggsHatch, 90)
        XCTAssertEqual(nest.failEggsHatch, 10)
        XCTAssertEqual(nest.eggsUnhatched, 5)
        XCTAssertEqual(nest.nextInspectionDate, nextInspection)
    }

    func testInspectionInsertUsesCurrentColumns() throws {
        let nestID = UUID()
        let dto = RecordInspectionInput(
            nestID: nestID,
            inspectedOn: Date(),
            outcome: .complete,
            eggsHatched: 70,
            eggsRotten: 30,
            nextInspectionDate: nil
        ).toDTO()

        let object = try encodedObject(dto)

        XCTAssertEqual(object["nest_id"] as? String, nestID.uuidString)
        XCTAssertEqual(object["outcome"] as? String, "complete")
        XCTAssertEqual(object["eggs_hatched"] as? Int, 70)
        XCTAssertEqual(object["eggs_rotten"] as? Int, 30)
    }

    func testNestInsertIncludesPredictedHatchColumn() {
        let predictedHatch = Date()
        let input = CreateNestInput(
            hatcheryID: UUID(),
            founderID: nil,
            numberOfEggs: 100,
            dateEggsLaid: nil,
            datePredictedHatch: predictedHatch,
            placementRow: 1,
            placementColumn: 2
        )

        XCTAssertEqual(input.toDTO().datePredictedHatch, predictedHatch)
    }

    func testDeviceSaveUsesAssignmentRPCParameters() throws {
        let deviceID = UUID()
        let nestID = UUID()
        let dto = UpdateDeviceInput(name: "Probe A", nestID: nestID)
            .toSaveDTO(deviceID: deviceID)

        let object = try encodedObject(dto)

        XCTAssertEqual(object["p_device_id"] as? String, deviceID.uuidString)
        XCTAssertEqual(object["p_name"] as? String, "Probe A")
        XCTAssertEqual(object["p_nest_id"] as? String, nestID.uuidString)
        XCTAssertNil(object["nest_id"], "The client must use save_device, not a mutable device.nest_id column.")
    }

    func testIoTDataDTOMapsToAReading() throws {
        let id = UUID()
        let nestID = UUID()
        let sensorID = UUID()
        let timestamp = Date()
        let dto = IoTDataDTO(
            id: id,
            nestID: nestID,
            sensorID: sensorID,
            position: "centre",
            depthCM: 45,
            temperature: 29.5,
            timestamp: timestamp,
            alert: "low",
            sensorStatus: "online",
            batteryVoltage: 3.7,
            signalRSSIDBM: -70
        )

        let reading = try dto.toEntity()

        XCTAssertEqual(reading.nestID, nestID)
        XCTAssertEqual(reading.sensorID, sensorID)
        XCTAssertEqual(reading.temperatureC, 29.5)
        XCTAssertEqual(reading.timestamp, timestamp)
        XCTAssertEqual(reading.alert, .low)
        XCTAssertEqual(reading.sensorStatus, .online)
        XCTAssertEqual(reading.depthCM, 45)
    }

    /// Temperature is the reason a reading exists, so its absence is the one
    /// thing that makes a row unusable.
    func testIoTDataWithoutTemperatureCannotMap() {
        let dto = IoTDataDTO(
            id: UUID(),
            nestID: UUID(),
            sensorID: nil,
            position: nil,
            depthCM: nil,
            temperature: nil,
            timestamp: Date(),
            alert: nil,
            sensorStatus: nil,
            batteryVoltage: nil,
            signalRSSIDBM: nil
        )

        XCTAssertThrowsError(try dto.toEntity())
    }

    /// Firmware reporting a status the app does not know must not hide an
    /// otherwise valid temperature.
    func testUnknownEnumValuesAreDroppedNotFatal() throws {
        let dto = IoTDataDTO(
            id: UUID(),
            nestID: UUID(),
            sensorID: nil,
            position: nil,
            depthCM: nil,
            temperature: 31.2,
            timestamp: Date(),
            alert: "meltdown",
            sensorStatus: "unplugged",
            batteryVoltage: nil,
            signalRSSIDBM: nil
        )

        let reading = try dto.toEntity()

        XCTAssertEqual(reading.temperatureC, 31.2)
        XCTAssertNil(reading.alert)
        XCTAssertNil(reading.sensorStatus)
    }

    // MARK: - Hatching audit columns

    func testNestDTOMapsCreatedAt() throws {
        let data = Data(
            """
            {
              "id": "\(UUID().uuidString)",
              "hatchery_id": "\(UUID().uuidString)",
              "number_of_eggs": 100,
              "placement_row": 0,
              "placement_col": 0,
              "created_at": "2026-06-15T00:00:00Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let nest = try decoder.decode(NestDTO.self, from: data).toEntity()

        XCTAssertEqual(nest.createdAt, Date(timeIntervalSince1970: 1_781_481_600))
    }

    func testHatchingDTOMapsRecorderAndCreatedAt() throws {
        let recorder = UUID()
        let data = Data(
            """
            {
              "id": "\(UUID().uuidString)",
              "nest_id": "\(UUID().uuidString)",
              "hatched_on": "2026-06-20T00:00:00Z",
              "eggs_hatched": 90,
              "eggs_rotten": 5,
              "eggs_unhatched": 5,
              "recorded_by": "\(recorder.uuidString)",
              "created_at": "2026-06-21T00:00:00Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let hatching = try decoder.decode(HatchingDTO.self, from: data).toEntity()

        XCTAssertEqual(hatching.recordedBy, recorder)
        XCTAssertNotNil(hatching.createdAt)
    }

    /// `recorded_by` is stamped by the assign_hatching_recorder trigger from
    /// `auth.uid()`, and `created_at` by a column default. Sending either would
    /// be ignored by Postgres -- and `created_at` is a `timestamptz` the shared
    /// encoder would flatten to a bare `yyyy-MM-dd` on the way out. This is the
    /// regression that would otherwise reach production in silence.
    func testHatchingInsertOmitsServerOwnedColumns() throws {
        let dto = RecordHatchingInput(
            nestID: UUID(),
            hatchedOn: Date(),
            eggsHatched: 90,
            eggsRotten: 5,
            eggsUnhatched: 5
        ).toDTO()

        let object = try encodedObject(dto)

        XCTAssertNil(object["recorded_by"])
        XCTAssertNil(object["created_at"])
        XCTAssertEqual(object["eggs_hatched"] as? Int, 90)
    }

    func testNestInsertAndUpdateOmitCreatedAt() throws {
        let insert = try encodedObject(
            CreateNestInput(
                hatcheryID: UUID(),
                founderID: nil,
                numberOfEggs: 100,
                dateEggsLaid: Date(),
                datePredictedHatch: nil,
                placementRow: 0,
                placementColumn: 0,
                nextInspectionDate: nil
            ).toDTO()
        )

        XCTAssertNil(insert["created_at"])
    }

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
