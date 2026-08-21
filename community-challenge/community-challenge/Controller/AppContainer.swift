import Foundation

/// The one composition root for dependencies.
///
/// Every repository is Supabase-backed. Readings will still be absent until a
/// sensor actually writes to `public.iotdata`, but that is now an empty table
/// rather than an in-memory stand-in. `hatchery` and `nest` additionally
/// require a per-device identity, since ownership is enforced at the database.
@MainActor
final class AppContainer {
    private let authenticationService: SupabaseAuthenticationService
    private let hatcheryRepository: SupabaseHatcheryRepository
    private let nestRepository: SupabaseNestRepository
    private let ioTDataRepository: SupabaseIoTDataRepository
    private let inspectionRepository: SupabaseInspectionRepository
    private let deviceRepository: SupabaseDeviceRepository
    private let hatchingRepository: SupabaseHatchingRepository
    private let profileRepository: SupabaseProfileRepository
    private let layoutService: HatcheryLayoutService

    init() {
        let client = SupabaseConfig.client
        let identity = SupabaseAuthenticationService(client: client)

        self.authenticationService = identity

        let hatcheryRepository = SupabaseHatcheryRepository(
            client: client,
            identity: identity
        )
        let nestRepository = SupabaseNestRepository(
            client: client,
            identity: identity
        )
        let layoutRepository = SupabaseHatcheryLayoutRepository(
            client: client,
            identity: identity
        )
        let photoStore = SupabaseHatcheryPhotoStore(
            client: client,
            identity: identity
        )
        self.hatcheryRepository = hatcheryRepository
        self.nestRepository = nestRepository
        self.ioTDataRepository = SupabaseIoTDataRepository(
            client: client,
            identity: identity
        )
        self.inspectionRepository = SupabaseInspectionRepository(client: client)
        self.deviceRepository = SupabaseDeviceRepository(
            client: client,
            identity: identity
        )
        self.hatchingRepository = SupabaseHatchingRepository(client: client, identity: identity)
        self.profileRepository = SupabaseProfileRepository(
            client: client,
            identity: identity
        )
        self.layoutService = HatcheryLayoutService(
            repository: layoutRepository,
            photoStore: photoStore
        )
    }

    private lazy var hatcheryService = HatcheryService(
        hatcheryRepository: hatcheryRepository,
        nestRepository: nestRepository,
        ioTDataRepository: ioTDataRepository
    )

    private lazy var nestService = NestService(repository: nestRepository)

    private lazy var inspectionService = InspectionService(repository: inspectionRepository)

    private lazy var deviceService = DeviceService(repository: deviceRepository)

    private lazy var hatchingService = HatchingService(
        repository: hatchingRepository,
        nestRepository: nestRepository
    )

    func makeHatcherySetupController(
        editingHatchery: HatcheryEntity? = nil
    ) -> HatcherySetupController {
        HatcherySetupController(
            hatcheryService: hatcheryService,
            layoutService: layoutService,
            existingHatchery: editingHatchery
        )
    }

    func makeHatcheryController(
        sessionState: HatcherySessionState
    ) -> HatcheryController {
        HatcheryController(
            sessionState: sessionState,
            hatcheryService: hatcheryService
        )
    }

    func makeNestService() -> NestService { nestService }

    func makeNestDetailController(nestID: UUID) -> NestDetailController {
        NestDetailController(
            nestID: nestID,
            ioTDataRepository: ioTDataRepository,
            inspectionService: inspectionService,
            nestService: nestService,
            profileRepository: profileRepository,
            hatchingService: hatchingService
        )
    }

    func makeHatchingController(nest: NestEntity) -> HatchingController {
        HatchingController(
            nest: nest,
            hatchingService: hatchingService,
            ioTDataRepository: ioTDataRepository
        )
    }

    func makeNestController(hatcheryID: UUID) -> NestController {
        NestController(
            hatcheryID: hatcheryID,
            nestService: nestService,
            identity: authenticationService,
            deviceService: deviceService
        )
    }

    /// Joins the organization the code belongs to. The database owns every
    /// rule here — expiry, single use, and who the code was issued by — so a
    /// refusal propagates rather than being interpreted client-side.
    func redeemInvite(code: String) async throws {
        try await profileRepository.redeemInvite(code: code)
    }

    /// Deletes the signed-in account, then drops the local session so the app
    /// cannot keep using a token whose user no longer exists.
    func deleteAccount() async throws {
        // Before the RPC, not after: `source_photo_path` is the only record of
        // which object belongs to whom, and the rows holding it are about to be
        // deleted. Afterwards the files would be unreachable -- the bucket's
        // delete policy is written against a layout row that would no longer
        // exist -- so this is the last moment they can be removed at all.
        await layoutService.deleteCurrentUserPhotos()
        try await profileRepository.deleteAccount()
        try await authenticationService.signOut()
    }

    func signOut() async throws {
        try await authenticationService.signOut()
    }

    func makeProfileController() -> ProfileController {
        ProfileController(repository: profileRepository)
    }

    func makeHatcheryListController() -> HatcheryListController {
        HatcheryListController(
            hatcheryService: hatcheryService,
            layoutService: layoutService
        )
    }

    /// Completes the native Sign in with Apple flow using the same Supabase
    /// client and identity coordinator shared by all repositories.
    func signInWithApple(
        identityToken: String,
        nonce: String,
        fullName: String? = nil
    ) async throws {
        _ = try await authenticationService.signInWithApple(
            identityToken: identityToken,
            nonce: nonce
        )

        // These reads and writes are deliberately not swallowed. The earlier
        // `try?` here turned a failed save into a blank profile with nothing to
        // diagnose from — and for the name, the one chance to keep it had
        // already passed by the time anyone noticed.
        let existing = try await profileRepository.fetchCurrentProfile()

        // Apple supplies the name only on a person's first authorization, so
        // this is the one chance to keep it. A returning user sends none, and
        // blanking what is already stored would be worse than leaving it.
        var displayName = existing?.displayName
        if displayName?.isEmpty ?? true, let fullName, !fullName.isEmpty {
            displayName = fullName
        }

        // The address rides in the identity token on every sign-in, not just
        // the first, so it can always be recovered from the session. Fill it
        // only when the row has none, in case it was edited since.
        var appleEmail = existing?.appleEmail
        if appleEmail?.isEmpty ?? true,
           let sessionEmail = await profileRepository.currentSessionEmail(),
           !sessionEmail.isEmpty {
            appleEmail = sessionEmail
        }

        guard
            displayName != existing?.displayName || appleEmail != existing?.appleEmail
        else { return }

        _ = try await profileRepository.updateCurrentProfile(
            displayName: displayName,
            appleEmail: appleEmail
        )
    }

    // No UI consumes these yet; they are the composition points for the
    // inspection and device screens when those are built.
    func makeInspectionService() -> InspectionService { inspectionService }

    func makeDeviceService() -> DeviceService { deviceService }
}
