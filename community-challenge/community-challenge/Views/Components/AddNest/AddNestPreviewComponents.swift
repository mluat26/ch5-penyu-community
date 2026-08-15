import CoreLocation
import MapKit
import SwiftUI

struct AddNestPreviewCard: View {
    let nestNumber: String
    let eggCount: String
    let hatchDate: String
    let daysLeft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nest #\(nestNumber.isEmpty ? "—" : nestNumber)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)

                Rectangle()
                    .fill(Color(hex: "#EBEBEB"))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AddNestPreviewMetric(value: eggCount, label: "Eggs")
                        .frame(width: 108)

                    // "Month day, year" (Mar 01, 2026), not the field's own
                    // storage format (dd.MM.yyyy) that the raw draft holds.
                    AddNestPreviewMetric(
                        value: AppDateFormatting.longNestDraftDate(hatchDate),
                        label: "Ets. hatch *"
                    )
                    .frame(width: 112)

                    AddNestPreviewMetric(value: daysLeft, label: "Days left")
                }

                // The "Auto" badge on the hatch-date field already says this
                // once; the card presenting the whole set says it once more
                // for all of them, rather than repeating it per field.
                //
                // Interpolating a styled `Text` rather than `Text + Text`,
                // which is deprecated on this SDK.
                Text(
                    "* \(Text("Auto, the content auto generate by AI").foregroundStyle(Color.appGreenPrimary).fontWeight(.medium))"
                )
                .font(.caption2)
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(hex: "#939393").opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
    }
}

/// The identifiers that are not part of the headline summary: which bucket the
/// clutch is in, which grid cell it went to, and when someone is due to look at
/// it. Confirming these is the point of this screen, so they are shown rather
/// than trusted.
struct AddNestPreviewDetailRow: View {
    let bucketID: String
    let section: String
    let inspectionDate: String

    var body: some View {
        HStack(spacing: 0) {
            item(systemImage: "arrow.up.bin", label: "Bucket ID", value: bucketID)
            divider
            item(systemImage: "square.grid.3x3.square", label: "Section", value: section)
            divider
            item(systemImage: "dot.circle.viewfinder", label: "Inspection", value: inspectionDate)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Nest was found")
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))

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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F1F1F1").opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
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
        VStack(spacing: 4) {
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
    let temperatureC: Double
    let accentColor: Color

    var body: some View {
        VStack(spacing: 21) {
            Text("Current temperature")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appNeutralGray2.opacity(0.8))

            HStack(alignment: .top, spacing: 0) {
                Text(temperatureC.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 70, weight: .regular))
                    .frame(height: 48, alignment: .top)
                Text("°C")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(height: 48, alignment: .top)
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

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(isSecondary ? Color(hex: "#8E8E93") : Color(hex: "#FAF8F4"))
                .frame(maxWidth: .infinity, minHeight: 55)
        }
        .buttonStyle(.plain)
        .background(
            isSecondary ? Color(hex: "#F2F2F7") : Color.appGreenPrimary,
            in: RoundedRectangle(cornerRadius: 26)
        )
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }
}
