import XCTest
import Supabase
@testable import community_challenge

@MainActor
final class HatcheryNameUniquenessTests: XCTestCase {
    func testNameEntryRejectsCaseAndWhitespaceDuplicate() async throws {
        let existing = makeHatchery(name: "Hatch_01")
        let controller = HatcherySetupController(
            hatcheryService: makeService(seed: [existing])
        )

        do {
            try await controller.validateNewHatcheryName("  hatch_01  ")
            XCTFail("Expected a duplicate-name error")
        } catch let error as DomainValidationError {
            guard case .duplicateHatcheryName = error else {
                return XCTFail("Expected duplicate name, got \(error)")
            }
            XCTAssertEqual(error.localizedDescription, "Name already exists")
        }
    }

    func testInMemoryRepositoryAtomicallyRejectsConcurrentDuplicateNames() async throws {
        let repository = InMemoryHatcheryRepository()
        let firstInput = makeCreateInput(name: "Hatch_01")
        let secondInput = makeCreateInput(name: " hatch_01 ")

        let results = await withTaskGroup(
            of: Result<HatcheryEntity, Error>.self,
            returning: [Result<HatcheryEntity, Error>].self
        ) { group in
            group.addTask {
                do {
                    return .success(try await repository.create(firstInput))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                do {
                    return .success(try await repository.create(secondInput))
                } catch {
                    return .failure(error)
                }
            }

            var results: [Result<HatcheryEntity, Error>] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(results.filter { if case .success = $0 { true } else { false } }.count, 1)
        let hatcheries = try await repository.fetchAll()
        XCTAssertEqual(hatcheries.count, 1)

        let failure = try XCTUnwrap(results.first { if case .failure = $0 { true } else { false } })
        guard case let .failure(error as DomainValidationError) = failure,
              case .duplicateHatcheryName = error else {
            return XCTFail("Expected a duplicate-name error")
        }
    }

    func testRenameRejectsAnExistingHatcheryName() async throws {
        let first = makeHatchery(name: "Hatch_01")
        let second = makeHatchery(name: "Hatch_02")
        let service = makeService(seed: [first, second])

        do {
            _ = try await service.updateHatchery(
                id: second.id,
                UpdateHatcheryInput(
                    name: " hatch_01 ",
                    numberOfRows: second.numberOfRows,
                    numberOfColumns: second.numberOfColumns,
                    lengthM: second.lengthM,
                    widthM: second.widthM
                )
            )
            XCTFail("Expected a duplicate-name error")
        } catch let error as DomainValidationError {
            guard case .duplicateHatcheryName = error else {
                return XCTFail("Expected duplicate name, got \(error)")
            }
        }
    }

    func testSupabaseDuplicateConflictMapsToDomainError() {
        let mappedError = HatcheryPersistenceErrorMapper.map(
            PostgrestError(
                details: "hatchery_owner_normalized_name_unique",
                code: "23505",
                message: "Name already exists"
            )
        )

        guard let domainError = mappedError as? DomainValidationError,
              case .duplicateHatcheryName = domainError else {
            return XCTFail("Expected the database conflict to map to duplicate name")
        }
    }

    private func makeService(seed: [HatcheryEntity]) -> HatcheryService {
        HatcheryService(
            hatcheryRepository: InMemoryHatcheryRepository(seed: seed),
            nestRepository: InMemoryNestRepository(),
            ioTDataRepository: InMemoryIoTDataRepository()
        )
    }

    private func makeHatchery(name: String) -> HatcheryEntity {
        HatcheryEntity(
            id: UUID(),
            name: name,
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 7,
            lengthM: 5,
            widthM: 7,
            organizationID: nil
        )
    }

    private func makeCreateInput(name: String) -> CreateHatcheryInput {
        CreateHatcheryInput(
            name: name,
            shape: .rectangle,
            numberOfRows: 3,
            numberOfColumns: 7,
            lengthM: 5,
            widthM: 7,
            organizationID: nil
        )
    }
}
