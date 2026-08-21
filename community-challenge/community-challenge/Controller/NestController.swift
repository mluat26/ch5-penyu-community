import Foundation
import Observation

@MainActor
@Observable
final class NestController {
    var draft = NestFormDraft.sample
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var lastSavedNest: NestEntity?

    private let hatcheryID: UUID
    private let nestService: NestService
    /// Resolves the signed-in user, so a saved nest records who collected it.
    private let identity: (any SupabaseIdentityProviding)?
    /// Installs the logger named by the bucket ID into the saved nest.
    private let deviceService: DeviceService?

    init(
        hatcheryID: UUID,
        nestService: NestService,
        identity: (any SupabaseIdentityProviding)? = nil,
        deviceService: DeviceService? = nil
    ) {
        self.hatcheryID = hatcheryID
        self.nestService = nestService
        self.identity = identity
        self.deviceService = deviceService
    }

    /// The current user, or nil if the identity could not be resolved. A nest
    /// is still worth saving without its founder, so this never throws.
    private func currentUserID() async -> UUID? {
        try? await identity?.ensureAuthenticatedUserID()
    }

    func save() async -> NestEntity? {
        guard let eggCount = Int(draft.numberOfEggs), eggCount > 0 else {
            errorMessage = "Enter a valid number of eggs."
            return nil
        }

        guard let sectionRow = draft.sectionRow, let sectionColumn = draft.sectionColumn else {
            errorMessage = "Select a section on the map."
            return nil
        }

        // Defensive, not decorative: the timeline screen keeps both derived
        // dates current as the draft changes, but save() must not simply trust
        // that every UI path remembered to call the updater. Recomputing here
        // guarantees the persisted value matches the draft's own inputs
        // regardless of how the user got here.
        refreshDerivedDates()

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let founderID = await currentUserID()

            let nest = try await nestService.createNest(
                CreateNestInput(
                    hatcheryID: hatcheryID,
                    // Who collected this nest. The infobook calls this the
                    // founder / responsible person, and the detail screen
                    // shows it as "Data logger".
                    founderID: founderID,
                    numberOfEggs: eggCount,
                    dateEggsLaid: AppDateFormatting.parseNestDraftDate(draft.collectionDate),
                    datePredictedHatch: AppDateFormatting.parseNestDraftDate(draft.hatchDate),
                    bucketID: trimmedOrNil(draft.bucketID),
                    nestNumber: trimmedOrNil(draft.nestNumber),
                    // Nil unless the optional map step was completed. The
                    // database rejects one coordinate without the other, so
                    // they are only ever written as a pair.
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    locationAddress: draft.locationAddress,
                    placementRow: sectionRow,
                    placementColumn: sectionColumn,
                    // Queues the nest for its first visit. The wizard already
                    // asks for this date; without persisting it the nest is
                    // never due for inspection and nobody is prompted to look.
                    nextInspectionDate: AppDateFormatting.parseNestDraftDate(
                        draft.inspectionDate
                    )
                )
            )
            await installLogger(named: draft.bucketID, into: nest)

            lastSavedNest = nest
            return nest
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Assigns the logger the bucket ID names to this nest.
    ///
    /// Readings carry only the device's own ID; the database resolves the nest
    /// from the active assignment. Without this step a nest records a bucket
    /// ID as text and nothing else, the assignment never exists, and every
    /// reading that device sends is refused.
    ///
    /// Loggers are registered ahead of time -- the firmware is flashed with the
    /// ID of an existing row -- so this only ever installs one that is already
    /// there. It never creates a device: a new row would carry a new ID that no
    /// hardware knows, which looks like success and reports nothing.
    ///
    /// The nest is already saved by this point, so a missing logger never
    /// discards the record. It no longer reports itself either: the bucket ID
    /// is auto-issued until the NFC scan exists, so it matched no registered
    /// device and the warning fired on every nest. A genuine failure to reach
    /// the device service still surfaces -- that is a fault, not an absence.
    private func installLogger(named bucketID: String, into nest: NestEntity) async {
        let name = bucketID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let deviceService else { return }

        do {
            let devices = try await deviceService.devices()
            guard
                let device = devices.first(where: {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(name) == .orderedSame
                })
            else {
                // ponytail: silent by request -- the team guarantees the
                // logger is registered and powered before a nest is created,
                // so the warning was only ever noise in practice.
                //
                // If nests start reading "--" forever, look here first: no
                // device means no `device_assignment` row, and
                // `resolve_reading_nest` refuses every reading without one.
                return
            }

            _ = try await deviceService.updateDevice(
                id: device.id,
                UpdateDeviceInput(name: device.name, nestID: nest.id)
            )
        } catch {
            errorMessage = "Nest saved, but its logger could not be installed: \(error.localizedDescription)"
        }
    }

    /// The next identifier in a hatchery's sequence: one past the highest
    /// number already issued, three digits, starting at 001.
    nonisolated static func nextIdentifier(after existing: [String?]) -> String {
        let highest = existing.compactMap { $0.flatMap(Int.init) }.max() ?? 0
        return String(format: "%03d", highest + 1)
    }

    /// Issues both identifiers for a new nest. Neither is typed: the nest
    /// number continues the hatchery's sequence, and the bucket ID mirrors it
    /// until an NFC tag supplies the real one.
    ///
    /// A failed lookup leaves the draft's own defaults in place rather than
    /// blanking the screen, so the form stays saveable offline.
    // ponytail: numbered client-side from max + 1, and the bucket ID is a
    // stand-in for the tag payload. Replace that half with the NFC read; move
    // the nest number to a database sequence if two devices ever register into
    // one hatchery at the same moment.
    func prepareIdentifiers() async {
        guard let nests = try? await nestService.nests(hatcheryID: hatcheryID) else { return }
        let next = Self.nextIdentifier(after: nests.map(\.nestNumber))
        draft.nestNumber = next
        draft.bucketID = next
    }

    func reset() {
        draft = .sample
        errorMessage = nil
        lastSavedNest = nil
    }

    /// Whitespace typed into an optional field is not a value. Storing " "
    /// would make the nest look labelled while displaying as blank.
    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Both are asked for on the identity screen and both are required: a nest
    /// with no section cannot be drawn on the grid, and one with no pin cannot
    /// be found again on the beach.
    var isSectionMissing: Bool { draft.sectionRow == nil || draft.sectionColumn == nil }
    var isLocationMissing: Bool { draft.latitude == nil || draft.longitude == nil }

    /// Pure on purpose. It used to write a message into `errorMessage`, which
    /// nothing erased once the field was filled, so a fixed problem kept
    /// complaining. The screen now renders one message per missing field
    /// straight from the flags above, so filling a field clears its own
    /// message and the two cannot drift apart.
    ///
    /// The bucket ID and nest number are no longer checked: both are issued by
    /// `prepareIdentifiers()` and default to 001, so neither can be empty.
    func validateIdentity() -> Bool {
        !isSectionMissing && !isLocationMissing
    }

    /// The reference incubation duration from `SmartNest_Infobook_V01.pdf`,
    /// which gives roughly 80-82 days at 26C, 56 at 30C and 45-48 at 32C.
    ///
    /// 56 is the 30C figure, and this stays a single number on purpose: the
    /// infobook wants the duration configurable rather than derived, and an
    /// estimate that moved with every logged reading would be a promise the app
    /// cannot keep. It seeds the estimate; nothing recalculates it afterwards,
    /// per the infobook's "never overwrite the original estimate".
    ///
    /// ponytail: one constant for every species and temperature; split when
    /// the app tracks more than one species, or when the team wants the
    /// duration to follow the nest's own average.
    static let estimatedIncubationDays = 56

    /// The hatch estimate follows the collection date alone.
    ///
    /// It used to be `collection + daysAfterCollection`, which quietly tied it
    /// to the inspection interval: choosing to inspect in 5 days also claimed
    /// the eggs would hatch in 5 days.
    func updateEstimatedHatchDate() {
        // A date entered by hand wins. The infobook is explicit that the
        // estimate must never be overwritten once recorded, and 56 days is a
        // reference figure for 30C, not a fact about this nest.
        guard !draft.hasManualHatchDate else { return }

        guard
            let collectionDate = AppDateFormatting.parseNestDraftDate(draft.collectionDate),
            let estimatedDate = Calendar.current.date(
                byAdding: .day,
                value: Self.estimatedIncubationDays,
                to: collectionDate
            )
        else {
            return
        }

        draft.hatchDate = AppDateFormatting.nestDraftDateString(estimatedDate)
    }

    /// Resolves "inspect N days after collection" into the actual date, which
    /// is what `next_inspection_date` stores and what schedules the visit.
    ///
    /// Without this the mode was inert: the number was never applied, so every
    /// nest created this way was saved with whatever date the form happened to
    /// start with.
    func updateInspectionDateFromDays() {
        guard
            draft.inspectionDateMode == .afterCollectionDays,
            let collectionDate = AppDateFormatting.parseNestDraftDate(draft.collectionDate),
            let days = Int(draft.daysAfterCollection),
            days >= 0,
            let inspectionDate = Calendar.current.date(
                byAdding: .day,
                value: days,
                to: collectionDate
            )
        else {
            return
        }

        draft.inspectionDate = AppDateFormatting.nestDraftDateString(inspectionDate)
    }

    /// The reverse of `updateInspectionDateFromDays()`: picking a date directly
    /// resolves back into a day count, so the two stay in agreement.
    ///
    /// Without this, picking a date in "Select date" mode only ever wrote
    /// `inspectionDate` -- `daysAfterCollection` sat wherever it last was, so
    /// switching to "After X days" silently discarded the picked date and
    /// replaced it with a stale count that had nothing to do with what was
    /// just chosen.
    ///
    /// Guarded the same way its counterpart is: meaningful only while a date
    /// is the field the user is actually driving. A date before the
    /// collection date floors at 0 rather than saving a negative count.
    func updateDaysAfterCollectionFromInspectionDate() {
        guard
            draft.inspectionDateMode == .selectDate,
            let collectionDate = AppDateFormatting.parseNestDraftDate(draft.collectionDate),
            let inspectionDate = AppDateFormatting.parseNestDraftDate(draft.inspectionDate)
        else {
            return
        }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: collectionDate),
            to: Calendar.current.startOfDay(for: inspectionDate)
        ).day ?? 0

        draft.daysAfterCollection = String(max(days, 0))
    }

    /// Recomputes both derived dates from the draft's own inputs. Called when
    /// the timeline screen appears -- so a fresh draft's placeholder dates are
    /// replaced before anyone sees them -- and defensively again in `save()`.
    func refreshDerivedDates() {
        updateEstimatedHatchDate()
        updateInspectionDateFromDays()
    }

    /// Days from today until the estimated hatch, for the preview summary.
    /// Previously a hardcoded "90" that ignored every date on the form.
    var daysUntilHatchDisplay: String {
        guard let hatchDate = AppDateFormatting.parseNestDraftDate(draft.hatchDate) else {
            return "—"
        }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: hatchDate)
        ).day ?? 0
        return days > 0 ? "\(days)" : "0"
    }
}
