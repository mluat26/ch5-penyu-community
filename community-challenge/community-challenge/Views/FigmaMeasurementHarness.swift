import SwiftUI

#if DEBUG

/// Renders one Figma-backed screen full-bleed with the design's own sample
/// values, so a simulator screenshot can be diffed against the Figma export.
///
/// Driven by the `FIGMA_SCREEN` environment variable rather than a source
/// edit, so a measurement pass does not require touching the app entry point
/// between screens. Absent or unknown, the real app runs.
///
/// Fixture values are Figma's, not the database's: measuring against live data
/// would compare a different string's width and report drift that is not
/// there. Note `simctl` only forwards variables prefixed `SIMCTL_CHILD_`.
enum FigmaMeasurementHarness {
    static var requestedScreen: String? {
        ProcessInfo.processInfo.environment["FIGMA_SCREEN"]
    }

    @ViewBuilder
    static func view(for screen: String) -> some View {
        switch screen {
        case "invite":
            InvitationCodeView(invite: Fixtures.invite, onBack: {}, onRegenerate: {})

        case "join-empty":
            JoinWithCodeView(onJoin: { _ in }, onBack: {})

        case "join-complete":
            JoinWithCodeView(initialCode: "3333", onJoin: { _ in }, onBack: {})

        // Presented as real sheets rather than framed views: `.ignoresSafeArea`
        // inside them defeats an outer frame, and only a genuine presentation
        // reproduces Figma's 6pt inset and corner radius.
        case "profile-view", "profile-edit":
            SheetHost {
                ProfileSheetView(
                    controller: Fixtures.profileController,
                    onClose: {},
                    onSignOut: {},
                    onShowInvite: { _ in },
                    onDeleteAccount: {},
                    startsEditing: screen == "profile-edit"
                )
                .presentationDetents([.height(ProfileSheetView.Layout.detentHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationSizing(.page)
            }

        case "nest-detail":
            SheetHost {
                NestDetailSheet(
                    item: Fixtures.nestItem,
                    ordinal: 23,
                    sectionLabel: "B1",
                    controller: Fixtures.nestDetailController,
                    onClose: {},
                    onDelete: {}
                )
                .presentationDetents([.height(NestDetailSheet.Layout.detentHeight)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationSizing(.page)
            }

        default:
            Text("Unknown FIGMA_SCREEN “\(screen)”")
                .font(.system(size: 17, weight: .semibold))
        }
    }

    /// Sample values taken from the Figma frames themselves.
    enum Fixtures {
        static let invite = OrganizationInviteEntity(
            code: "3333",
            expiresAt: Date().addingTimeInterval(600)
        )

        @MainActor
        static var profileController: ProfileController {
            let controller = ProfileController(repository: StubProfileRepository())
            return controller
        }

        static var nest: NestEntity {
            NestEntity(
                id: UUID(),
                hatcheryID: UUID(),
                numberOfEggs: 490,
                dateEggsLaid: Calendar.current.date(byAdding: .day, value: -20, to: .now),
                datePredictedHatch: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                bucketID: "PN124",
                nestNumber: "01",
                locationAddress: "Kuta Beach",
                placementRow: 0,
                placementColumn: 1,
                nextInspectionDate: Calendar.current.date(byAdding: .day, value: -57, to: .now)
            )
        }

        static var nestItem: NestDashboardItem {
            NestDashboardItem(
                nest: nest,
                latestTemperatureC: 29.0,
                latestBatteryVoltage: 4.2
            )
        }

        @MainActor
        static var nestDetailController: NestDetailController {
            NestDetailController(
                nestID: UUID(),
                ioTDataRepository: StubIoTDataRepository(),
                inspectionService: InspectionService(repository: StubInspectionRepository())
            )
        }
    }
}

/// Presents its content as a sheet over a plain backdrop, so a screenshot
/// captures the same presentation the app uses.
private struct SheetHost<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var isPresented = false

    var body: some View {
        Color.white
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) { content }
            .onAppear { isPresented = true }
    }
}

// MARK: - Stubs

/// Returns the profile the Figma frames show, without touching the network.
private struct StubProfileRepository: ProfileRepository {
    func fetchCurrentProfile() async throws -> ProfileEntity? {
        ProfileEntity(
            id: UUID(),
            displayName: "Alena",
            appleEmail: "Missaler",
            organizationID: UUID(),
            role: .manager
        )
    }

    func fetchProfile(id: UUID) async throws -> ProfileEntity? {
        try await fetchCurrentProfile()
    }

    func updateCurrentProfile(displayName: String?, appleEmail: String?) async throws -> ProfileEntity {
        try await fetchCurrentProfile()!
    }

    func fetchOrganization(id: UUID) async throws -> OrganizationEntity {
        OrganizationEntity(id: id, name: "Demo", createdAt: .now, code: "ORG-0000000")
    }

    func generateInvite() async throws -> OrganizationInviteEntity {
        FigmaMeasurementHarness.Fixtures.invite
    }

    func redeemInvite(code: String) async throws -> UUID { UUID() }

    func deleteAccount() async throws {}
}

/// A day of readings shaped like the chart in 166:3082 — a rise through the
/// morning, a mid-afternoon peak, then a fall.
private struct StubIoTDataRepository: IoTDataRepository {
    func fetchReadings(nestIDs: [UUID], in interval: DateInterval?) async throws -> [IoTDataEntity] {
        guard let nestID = nestIDs.first else { return [] }
        let start = Calendar.current.startOfDay(for: .now)

        return (0..<20).map { slot in
            let hour = Double(slot) * 24.0 / 28.0
            return IoTDataEntity(
                id: UUID(),
                nestID: nestID,
                sensorID: UUID(),
                temperatureC: 26.5 + 5.5 * sin((hour - 4) / 24 * 2 * .pi),
                timestamp: start.addingTimeInterval(hour * 3600),
                batteryVoltage: 4.2
            )
        }
    }

    func fetchAll(nestID: UUID) async throws -> [IoTDataEntity] {
        try await fetchReadings(nestIDs: [nestID], in: nil)
    }

    /// The harness renders charts, which read whole series. Nothing here asks
    /// for a reading by ID, so this throws rather than inventing one — a
    /// fabricated row would quietly corrupt a measurement run.
    func fetch(id: UUID) async throws -> IoTDataEntity {
        throw RepositoryError.notFound(resource: "IoTData", id: id)
    }
}

private struct StubInspectionRepository: InspectionRepository {
    func fetchAll(nestID: UUID) async throws -> [InspectionEntity] {
        (1...3).map { index in
            InspectionEntity(
                id: UUID(),
                nestID: nestID,
                inspectedOn: Calendar.current.date(
                    byAdding: .day, value: -30 + index * 10, to: .now
                ) ?? .now,
                outcome: .notHatched
            )
        }
    }

    func create(_ input: RecordInspectionInput) async throws -> InspectionEntity {
        try await fetchAll(nestID: input.nestID).first!
    }

    func update(id: UUID, _ input: CorrectInspectionInput) async throws -> InspectionEntity {
        try await fetchAll(nestID: UUID()).first!
    }
}

#endif
