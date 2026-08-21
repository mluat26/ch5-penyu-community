import CoreLocation
import MapKit
import SwiftUI

/// Figma 193:4230. The card leads with what it is -- a prediction, not a
/// record -- and says whose algorithm produced it, so the numbers below are
/// read as an estimate. The nest number moves to the right of the title: it
/// identifies the card rather than heading it.
struct AddNestPreviewCard: View {
    let nestNumber: String
    let eggCount: String
    let hatchDate: String
    let daysLeft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hatching prediction")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)

                        Spacer(minLength: 8)

                        Text("Nest #\(nestNumber.isEmpty ? "—" : nestNumber)")
                            .font(.footnote)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                    }

                    Text("The data is computed using the Penyu team's algorithm")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#0088FF").opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle()
                    .fill(Color(hex: "#EBEBEB"))
                    .frame(height: 1)
            }

            // Equal thirds. The estimate in the middle is the longest value, and
            // the metric shrinks its own text rather than stealing width from
            // the two counts either side.
            HStack(spacing: 12) {
                AddNestPreviewMetric(value: eggCount, label: "Eggs")

                // "Month day, year" (Mar 01, 2026), not the field's own
                // storage format (dd.MM.yyyy) that the raw draft holds.
                AddNestPreviewMetric(
                    value: AppDateFormatting.longNestDraftDate(hatchDate),
                    label: "Ets. hatch"
                )

                AddNestPreviewMetric(value: daysLeft, label: "Days left")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(hex: "#939393").opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// A flat row of identifiers, each an icon over a label over its value, split
/// by thin vertical rules. The caller decides which facts belong in it -- the
/// review screen shows bucket, section and inspection date, but nothing here
/// is tied to those three.
struct AddNestPreviewDetailRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let systemImage: String
        let label: String
        let value: String
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { divider }
                item(
                    systemImage: entry.systemImage,
                    label: entry.label,
                    value: entry.value
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: "#EBEBEB"))
            .frame(width: 1, height: 50)
    }

    /// Flat -- no card, no shadow, no shared border. The only separation
    /// between the three identifiers is the thin vertical rule.
    private func item(
        systemImage: String,
        label: String,
        value: String
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color(hex: "#8E8E93"))

            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))

            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// Where the eggs were found, which the grid placement deliberately does not
/// record: nests are relocated into the hatchery, so the origin beach is a
/// separate fact worth confirming before saving.
struct AddNestFoundLocationCard: View {
    let latitude: Double
    let longitude: Double
    let address: String?

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(address ?? "Dropped pin")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: "#2A2A2A"))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(NestLocationPickerView.formattedCoordinates(coordinate))
                    .font(.body)
                    .foregroundStyle(Color.appNeutralGray1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A still, non-interactive map: this is a confirmation, and a
            // pannable map here would compete with the page's own scroll.
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.004,
                            longitudeDelta: 0.004
                        )
                    )
                ),
                interactionModes: []
            ) {
                Marker("", coordinate: coordinate)
                    .tint(Color.appGreenPrimary)
            }
            .frame(width: 80, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F1F1F1").opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        // A hairline at 60%, not a full 1pt line. The fill is already within a
        // couple of percent of the page behind it, so the outline was what
        // made this read as a box competing with its own text.
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#EBEBEB").opacity(0.6), lineWidth: 0.5)
        }
    }
}

/// The saved pin, full size. Read-only on purpose: the preview is a review
/// step, so the map can be panned and zoomed to check the pin but not moved.
/// Changing it means going back to the form through "Edit details".
struct NestLocationPreviewSheet: View {
    let latitude: Double
    let longitude: Double
    let onClose: () -> Void

    enum Layout {
        /// Figma 197:4324 draws a 713pt sheet, less the 34pt bottom safe area
        /// iOS adds to a fixed detent -- the same arithmetic the profile and
        /// nest-detail sheets use.
        static let detentHeight: CGFloat = 679
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.004,
                        longitudeDelta: 0.004
                    )
                )
            )
        ) {
            Marker("Nest location", coordinate: coordinate)
                .tint(Color.appGreenPrimary)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appNeutralBlack)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
                    // Same reason as the picker's close button: `.plain`
                    // hit-tests rendered content, so the frame's corners
                    // outside the glass circle are dead without this.
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            // Figma 197:4327 pads its content by 10, and the toolbar's button
            // group adds its own 16 inside that.
            .padding(.top, 20)
            .padding(.leading, 26)
            .accessibilityLabel("Close map")
        }
    }
}

/// All three metrics on the preview card share one text style in the design
/// (Title3/Emphasized) -- there is no per-metric variation to encode, so
/// unlike the version this replaced, nothing here picks a different font for
/// the egg count. That was also the one hardcoded `.system(size:)` on this
/// screen: fixed points don't grow with the user's text-size setting the way
/// `.title3` does, so it was the one metric that stayed the same size while
/// its siblings scaled.
///
/// No icon: the design pairs each value with a bare caption, not a glyph.
private struct AddNestPreviewMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appNeutralGray2)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))
                .lineLimit(1)
                // The value above shrinks rather than truncates; without this
                // the label didn't, so the one metric with no fixed column
                // width ("Days left") clipped to "Days l..." instead.
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AddNestTemperatureCard: View {
    /// Nil until the nest's logger has reported, which is the ordinary state
    /// for a nest registered seconds ago. It reads "--" rather than a number,
    /// so a nest with no data cannot be mistaken for a healthy one.
    let temperatureC: Double?
    let accentColor: Color

    var body: some View {
        VStack(spacing: 21) {
            Text("Current temperature")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appNeutralGray2.opacity(0.8))

            HStack(alignment: .top, spacing: 0) {
                Text(NestTemperature.text(temperatureC))
                    .font(.system(size: 70, weight: .regular))
                    .frame(height: 48, alignment: .top)
                // No unit on an absent reading: "--°C" reads as a measurement
                // in degrees that happens to be missing its digits, when the
                // truth is that nothing has been measured at all.
                if temperatureC != nil {
                    Text("°C")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(height: 48, alignment: .top)
                }
            }
            .frame(height: 48, alignment: .top)
            .foregroundStyle(accentColor)
            .minimumScaleFactor(0.7)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 152)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 20)
    }
}

struct AddNestSummaryMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))

            Spacer(minLength: 0)

            Text(value)
                .font(title == "Eggs" ? .system(size: 20, weight: .semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(title == "Eggs" ? .black : Color(hex: "#2A2A2A"))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 85, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 20)
    }
}

/// Kept separate from `HatcheryPrimaryButton` because the Add Nest flow also
/// needs its filled secondary variation, which the location picker shares.
struct AddNestPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled = false
    /// The preview screen's "Edit details" is a real button in the design
    /// (a light-gray filled pill matching iOS's system gray-6), not a bare
    /// text link -- it needed the same shape as "Save nest", just muted.
    var isSecondary = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(isSecondary ? Color.black : Color(hex: "#FAF8F4"))
                .frame(maxWidth: .infinity, minHeight: 55)
                // Both inside the label, as `HatcheryPrimaryButton` does it.
                // `.plain` hit-tests rendered content, and the label was bare
                // text -- the pill was drawn by a view wrapping the button, so
                // it was never the button's to hit and only the word responded.
                .background(
                    isSecondary ? Color(hex: "#F2F2F7") : Color.appGreenPrimary,
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }
}
