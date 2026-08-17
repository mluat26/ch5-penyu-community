import CoreLocation
import MapKit
import SwiftUI

/// Supplies the device's own position, used only to say how far the pin is
/// from where the person is standing.
///
/// Kept deliberately small: nothing here tracks continuously, because a single
/// fix is all a distance label needs and a running GPS is expensive on a phone
/// carried around a beach all day.
@MainActor
@Observable
final class UserLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            // Denied or restricted. The pin still works; only the distance
            // line is dropped.
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard
                manager.authorizationStatus == .authorizedWhenInUse
                    || manager.authorizationStatus == .authorizedAlways
            else {
                return
            }
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let latest = locations.last
        MainActor.assumeIsolated { location = latest }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        // Nothing to show and nothing to recover: the distance line is omitted.
    }
}

/// `Label`'s default style pins the icon to the title's first-line baseline,
/// which looks fine for one line but leaves the icon floating above a
/// wrapped, multi-line title. This centers the icon against the whole title
/// block instead.
private struct CenteredLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.icon
            configuration.title
        }
    }
}

/// Records where a clutch was found, which is not where it ends up: eggs are
/// relocated into the hatchery, so the grid placement chosen on the previous
/// screen says nothing about the origin beach.
///
/// The pin is dropped by long press rather than by tapping. A tap is how the
/// map pans and zooms, and a beach is mostly featureless, so a stray tap while
/// framing the shot would otherwise silently move the record.
struct NestLocationPickerView: View {
    @Bindable var controller: NestController
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var camera: MapCameraPosition
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var placeName: String?
    @State private var addressLines: [String] = []
    @State private var isResolvingAddress = false
    /// Reverse geocoding is a network call and the pin can move faster than it
    /// answers. Keeping the task lets a new drop cancel the previous lookup so
    /// a slow reply cannot overwrite a newer pin's address.
    @State private var geocodeTask: Task<Void, Never>?
    @State private var userLocation = UserLocationProvider()

    init(
        controller: NestController,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.controller = controller
        self.onCancel = onCancel
        self.onSave = onSave

        let existing = controller.draft.latitude.flatMap { latitude in
            controller.draft.longitude.map { longitude in
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        _coordinate = State(initialValue: existing)
        _addressLines = State(
            initialValue: Self.lines(from: controller.draft.locationAddress)
        )
        _camera = State(
            initialValue: existing.map {
                .region(
                    MKCoordinateRegion(
                        center: $0,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.01,
                            longitudeDelta: 0.01
                        )
                    )
                )
            } ?? .userLocation(fallback: .automatic)
        )
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let coordinate {
                    Marker("Nest location", coordinate: coordinate)
                        .tint(Color.appGreenPrimary)
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        guard
                            case .second(_, let drag?) = value,
                            let dropped = proxy.convert(drag.location, from: .local)
                        else {
                            return
                        }
                        drop(dropped)
                    }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) { instruction }
            .overlay(alignment: .topLeading) { closeButton }
        }
        .task { userLocation.start() }
        // The card only exists once there is a place to describe. Background
        // interaction stays on so the map can still be panned behind it, and
        // the card cannot be swiped away -- dismissing it means clearing the
        // pin, which is what its own close button does.
        .sheet(isPresented: .constant(coordinate != nil)) {
            if let coordinate {
                PinnedLocationSheet(
                    coordinate: coordinate,
                    placeName: placeName,
                    addressLines: addressLines,
                    isResolvingAddress: isResolvingAddress,
                    distanceText: distanceText(to: coordinate),
                    onClear: clearPin,
                    onSave: { save(coordinate) }
                )
                .presentationDetents([.height(360), .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(360)))
                .interactiveDismissDisabled()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var instruction: some View {
        Label(
            coordinate == nil
                ? "Press and hold on the map to set the location pin."
                : "Press and hold again to move the pin.",
            systemImage: "hand.tap.fill"
        )
        // Label's default aligns the icon to the first line's text baseline,
        // which reads as "floating above" once the icon is scaled up and the
        // title wraps to two lines. Centering against the whole title block
        // keeps it visually level regardless of line count.
        .labelStyle(CenteredLabelStyle())
        .font(.body)
        .imageScale(.large)
        .foregroundStyle(Color.appNeutralGray1)
        // The text shortens once a pin exists. Reserving both lines and the
        // full width keeps the banner one fixed size across that swap.
        .lineLimit(2, reservesSpace: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.top, 70)
        .padding(.horizontal, 16)
    }

    private var closeButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appNeutralBlack)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.leading, 16)
        .accessibilityLabel("Cancel")
    }

    private func distanceText(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let userLocation = userLocation.location else { return nil }
        let target = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let metres = userLocation.distance(from: target)
        let formatted = Measurement(value: metres, unit: UnitLength.meters)
            .formatted(
                .measurement(width: .abbreviated, usage: .road)
            )
        return "\(formatted) away"
    }

    private func save(_ coordinate: CLLocationCoordinate2D) {
        controller.draft.latitude = coordinate.latitude
        controller.draft.longitude = coordinate.longitude
        controller.draft.locationAddress = addressLines.isEmpty
            ? nil
            : addressLines.joined(separator: ", ")
        onSave()
    }

    /// Clearing the pin is what closing the card means, the same way dismissing
    /// a place in Maps drops its marker. Leaving the pin with no card would
    /// strand it: there would be no way to confirm or remove it.
    private func clearPin() {
        geocodeTask?.cancel()
        coordinate = nil
        placeName = nil
        addressLines = []
        isResolvingAddress = false
    }

    private func drop(_ dropped: CLLocationCoordinate2D) {
        coordinate = dropped
        placeName = nil
        addressLines = []
        geocodeTask?.cancel()
        isResolvingAddress = true

        geocodeTask = Task {
            let resolved = await Self.resolvePlace(for: dropped)
            guard !Task.isCancelled else { return }
            placeName = resolved.name
            addressLines = resolved.lines
            isResolvingAddress = false
        }
    }

    /// A failed lookup is not an error worth surfacing: the coordinates are the
    /// record, and the address is a convenience on top of them.
    ///
    /// `CLGeocoder` is deprecated on this SDK, so this uses MapKit's
    /// replacement.
    private static func resolvePlace(
        for coordinate: CLLocationCoordinate2D
    ) async -> (name: String?, lines: [String]) {
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        guard
            let request = MKReverseGeocodingRequest(location: location),
            let item = try? await request.mapItems.first
        else {
            return (nil, [])
        }
        return (item.name, lines(from: item.address?.fullAddress))
    }

    /// The card lists an address a line at a time, the way a postal address is
    /// written, rather than as one run-on sentence.
    private static func lines(from address: String?) -> [String] {
        guard let address, !address.isEmpty else { return [] }
        return address
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Degrees with a hemisphere letter, matching how the design shows a
    /// position: signed decimals read as arithmetic, not as a place.
    static func formattedCoordinates(_ coordinate: CLLocationCoordinate2D) -> String {
        func format(_ value: Double, positive: String, negative: String) -> String {
            let magnitude = abs(value).formatted(
                .number.precision(.fractionLength(5)).grouping(.never)
            )
            return "\(magnitude)° \(value < 0 ? negative : positive)"
        }

        return format(coordinate.latitude, positive: "N", negative: "S")
            + ", "
            + format(coordinate.longitude, positive: "E", negative: "W")
    }
}

/// The place card for a dropped pin, following the shape Maps uses: share and
/// close flanking the name, then the details, then the action.
struct PinnedLocationSheet: View {
    let coordinate: CLLocationCoordinate2D
    let placeName: String?
    let addressLines: [String]
    let isResolvingAddress: Bool
    let distanceText: String?
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.appNeutralBlack)

                    detailRow(
                        label: "Address",
                        lines: addressLines.isEmpty ? [fallbackAddressLine] : addressLines
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            AddNestPrimaryButton(title: "Save", action: onSave)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appNeutralBlack)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "#EBEBEB"), in: Circle())
            }
            .accessibilityLabel("Share this location")

            VStack(spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.appNeutralBlack)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.appNeutralGray2.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appNeutralBlack)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "#EBEBEB"), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this pin")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func detailRow(label: String, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.appNeutralGray2.opacity(0.8))

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.body)
                        .foregroundStyle(Color.appNeutralBlack)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var title: String {
        if let placeName, !placeName.isEmpty { return placeName }
        return addressLines.first ?? "Dropped pin"
    }

    private var subtitle: String {
        let marked = "Marked Location"
        guard let distanceText else { return marked }
        return "\(marked) · \(distanceText)"
    }

    private var fallbackAddressLine: String {
        isResolvingAddress ? "Finding address…" : "No address found"
    }

    private var shareText: String {
        let place = [placeName].compactMap(\.self).filter { !$0.isEmpty }
        return (place + addressLines
            + [NestLocationPickerView.formattedCoordinates(coordinate)])
            .joined(separator: "\n")
    }
}

#Preview("Pick nest location", traits: .fixedLayout(width: 402, height: 874)) {
    NestLocationPickerView(
        controller: NestController(
            hatcheryID: UUID(),
            nestService: NestService(repository: InMemoryNestRepository())
        ),
        onCancel: { },
        onSave: { }
    )
}

// The map itself needs a device to render, so the card gets its own preview:
// it is the part with layout worth checking.
#Preview("Pinned location card", traits: .fixedLayout(width: 402, height: 874)) {
    PinnedLocationSheet(
        coordinate: CLLocationCoordinate2D(latitude: -8.72, longitude: 115.16),
        placeName: "Kuta Beach",
        addressLines: ["Jl. Pantai Kuta", "Kuta", "Badung", "Bali 80361"],
        isResolvingAddress: false,
        distanceText: "120 m away",
        onClear: { },
        onSave: { }
    )
}
