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
    /// Starting pin, if the caller already has one.
    let initialLatitude: Double?
    let initialLongitude: Double?
    let initialAddress: String?
    /// Preview mode: the pin can be looked at, panned around and shared, but
    /// not moved, cleared or saved. Used by the nest detail sheet when it is
    /// not in edit mode.
    let isReadOnly: Bool
    let onCancel: () -> Void
    /// Hands back the dropped pin and the address resolved for it, so this
    /// screen works for editing a saved nest as well as creating one.
    let onSave: (Double, Double, String?) -> Void

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
        initialLatitude: Double? = nil,
        initialLongitude: Double? = nil,
        initialAddress: String? = nil,
        isReadOnly: Bool = false,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Double, Double, String?) -> Void
    ) {
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
        self.initialAddress = initialAddress
        self.isReadOnly = isReadOnly
        self.onCancel = onCancel
        self.onSave = onSave

        let existing = initialLatitude.flatMap { latitude in
            initialLongitude.map { longitude in
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        _coordinate = State(initialValue: existing)
        _addressLines = State(initialValue: Self.lines(from: initialAddress))
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
            // This gesture belongs to the map, and the map is the whole screen
            // -- including the area behind the close button. A press there is
            // delivered to both, so holding the button a moment too long let
            // the map claim it and the button never fired. Presses inside the
            // button's own frame are not the map's to handle.
            .gesture(
                LongPressGesture(minimumDuration: 0.2)
                    // Global space, so the press location and the button's
                    // frame below are measured against the same origin. The
                    // gesture's own local space is the map's, which the
                    // overlay's geometry has no way to name.
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onEnded { value in
                        guard
                            case .second(_, let drag?) = value,
                            !closeButtonFrame.contains(drag.location),
                            let dropped = proxy.convert(drag.location, from: .global)
                        else {
                            return
                        }
                        drop(dropped)
                    },
                isEnabled: !isReadOnly
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                // Nothing to instruct when the pin cannot move.
                if !isReadOnly { instruction }
            }
            .overlay(alignment: .topLeading) {
                closeButton
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { closeButtonFrame = $0 }
            }
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
                    isReadOnly: isReadOnly,
                    onClose: onCancel,
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

    /// Where the close button sits in the map's own space, so the press that
    /// drops a pin can leave it alone. Zero until first laid out, and an empty
    /// rect contains nothing, so the guard is inert until it is real.
    @State private var closeButtonFrame: CGRect = .zero

    private var closeButton: some View {
        Button(action: cancel) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appNeutralBlack)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
                // `.plain` hit-tests rendered content, so without this the
                // corners of the frame outside the glass circle are dead.
                .contentShape(.circle)
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

    /// Leaving with the pin still set keeps the card presented through the pop,
    /// so it rides along on top of the form for a moment -- the same way saving
    /// used to. Clearing first is what takes the card down.
    private func cancel() {
        clearPin()
        onCancel()
    }

    private func save(_ coordinate: CLLocationCoordinate2D) {
        let address = addressLines.isEmpty ? nil : addressLines.joined(separator: ", ")

        // Take the card down before handing the pin back. Its presentation is
        // derived from `coordinate`, so leaving that set keeps the card on
        // screen through the pop -- visible for a moment over the form, with a
        // live Save button. Tapping it again popped a second time and landed
        // on the bucket screen. Values are read out first; clearing the pin is
        // what closes the card.
        clearPin()

        onSave(coordinate.latitude, coordinate.longitude, address)
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
    /// Preview mode: the card describes the pin but offers no way to change
    /// or commit it, so both actions are dropped.
    var isReadOnly = false
    /// Leaves a read-only preview. Unused while editing, where Save and the
    /// clear button are present instead.
    var onClose: () -> Void = {}
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

            if !isReadOnly {
                AddNestPrimaryButton(title: "Save", action: onSave)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
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

            if isReadOnly {
                // A preview has no Save and no pin to clear, and the sheet
                // cannot be swiped away, so without this there is no way out:
                // the map's own close button sits behind this sheet.
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appNeutralBlack)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "#EBEBEB"), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            } else {
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
    NestLocationPickerView(onCancel: { }, onSave: { _, _, _ in })
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
