/// Screens and state-local helpers for the Add Nest flow.
import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// The one screen ahead of the numbered stepper: prompts scanning the bucket's
/// NFC tag before the form begins. That scan isn't wired up yet, so nothing
/// here reads a real tag -- the whole page is a tap target standing in for
/// what will become an automatic advance once a bucket is detected.
struct AddNestConnectBucketView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(spacing: 12) {
                    Text("Connect your bucket")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appGreenPrimary)
                        .multilineTextAlignment(.center)

                    Text("Tap your bucket with the tag\nto register it")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 100)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)

                Image("AddNestBucketHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 68)
                    .accessibilityHidden(true)

                howItWorksCard
                    .padding(.horizontal, 16)
                    .padding(.top, 45)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            // Standing in for the real trigger: an NFC read will replace this
            // once that integration exists.
            //
            // `contentShape` + `onTapGesture` rather than a simultaneous
            // gesture on the whole ScrollView: that version also fired when
            // the close button was tapped, so X advanced the flow instead of
            // leaving it.
            .contentShape(Rectangle())
            .onTapGesture(perform: onContinue)

            AddNestFlowHeader(style: .closeOnly, onBack: nil, onClose: onCancel)
                .zIndex(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var howItWorksCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "iphone.gen2.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(Color.appGreenPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("How it works")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray2)

                    Text("Hold your iPhone near the NFC tag on the bucket until it's detected. Your Bucket ID will show up automatically.")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#AEAEB2"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#E0E0E0").opacity(0.29), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AddNestIdentityView: View {
    @Bindable var controller: NestController
    let onSelectSection: () -> Void
    let onPinLocation: () -> Void
    let onNext: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AddNestFlowTopHeader(currentStep: 1, onClose: onCancel)

                    VStack(alignment: .leading, spacing: 16) {
                        AddNestSectionTitle(title: "Nest identity")

                        // Figma 188:4127 drops the field boxes: both values are
                        // issued by the app, so showing them as editable
                        // controls invited edits that would break the sequence.
                        HStack(alignment: .top, spacing: 10) {
                            AddNestLabeledValue(
                                label: "Bucket ID",
                                value: controller.draft.bucketID
                            )

                            AddNestLabeledValue(
                                label: "Nest Number",
                                value: controller.draft.nestNumber
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Section")
                                .font(.subheadline)
                                .foregroundStyle(Color.appNeutralGray2)

                            AddNestDisclosureRow(
                                systemImage: "square.grid.2x2",
                                title: sectionTitle,
                                subtitle: sectionSubtitle,
                                isSelected: !controller.draft.section.isEmpty,
                                action: onSelectSection
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            AddNestSectionTitle(title: "Location")

                            AddNestDisclosureRow(
                                systemImage: isLocationPinned ? nil : "mappin",
                                title: locationTitle,
                                subtitle: locationSubtitle,
                                isSelected: isLocationPinned,
                                titleLineLimit: isLocationPinned ? 2 : 1,
                                action: onPinLocation
                            )
                        }

                        if let errorMessage = controller.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.appRed)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .containerRelativeFrame(.horizontal)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        // Issued here rather than when the flow starts, so the number reflects
        // any nest saved since -- and so returning to this screen re-reads it.
        .task { await controller.prepareIdentifiers() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HatcheryPrimaryButton(title: "Next") {
                guard controller.validateIdentity() else { return }
                onNext()
            }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(Color.white)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    /// The chosen value is emphasized inside the sentence rather than replacing
    /// it, so the row still reads as the same control once it is filled in.
    private var sectionTitle: Text {
        let section = controller.draft.section
        guard !section.isEmpty else { return Text("Select the section") }
        // Interpolating a styled `Text` rather than concatenating: `Text + Text`
        // is deprecated on this SDK.
        return Text(
            "Selected \(Text("section \(section)").foregroundStyle(Color.appGreenPrimary).fontWeight(.semibold))"
        )
    }

    private var sectionSubtitle: String {
        "Tap a grid cell to choose the nest location"
    }

    private var isLocationPinned: Bool {
        controller.draft.latitude != nil && controller.draft.longitude != nil
    }

    /// Once pinned the row describes the place itself: the address on top and
    /// its coordinates beneath, rather than a label saying something was
    /// chosen. Two lines, because a street address rarely fits in one.
    private var locationTitle: Text {
        guard isLocationPinned else { return Text("Pin the location") }
        if let address = controller.draft.locationAddress, !address.isEmpty {
            return Text(address)
        }
        return Text("Dropped pin")
    }

    private var locationSubtitle: String {
        guard
            isLocationPinned,
            let latitude = controller.draft.latitude,
            let longitude = controller.draft.longitude
        else {
            return "Record where were eggs found"
        }
        return NestLocationPickerView.formattedCoordinates(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }
}

struct AddNestEggInformationView: View {
    @Bindable var controller: NestController
    let onPreview: () -> Void
    let onCancel: () -> Void

    @State private var datePickerTarget: NestDatePickerTarget?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AddNestFlowTopHeader(currentStep: 2, onClose: onCancel)

                    AddNestBigNumberField(
                        label: "Total number of eggs",
                        text: $controller.draft.numberOfEggs,
                        focus: $isFieldFocused
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 30)

                    VStack(alignment: .leading, spacing: 10) {
                        AddNestSectionTitle(title: "Timeline")

                        AddNestTimelineDateBlock(
                            label: "Egg collection date",
                            value: controller.draft.collectionDate
                        ) {
                            toggle(.collection)
                        }

                        if datePickerTarget == .collection {
                            AddNestInlineDatePicker(
                                selection: dateBinding(for: .collection)
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Egg inspection date")
                                .font(.subheadline)
                                .foregroundStyle(Color.appNeutralGray2)

                            AddNestInspectionModeControl(
                                mode: controller.draft.inspectionDateMode
                            ) { newMode in
                                controller.draft.inspectionDateMode = newMode
                                // Switching mode has to apply the interval
                                // immediately; otherwise the date shown and
                                // the date saved are whatever the form was
                                // last left holding. A no-op when switching to
                                // select-date, which is user-driven instead.
                                controller.updateInspectionDateFromDays()
                            }
                        }

                        HStack {
                            Text(inspectionRowLabel)
                                .font(.footnote)
                                .foregroundStyle(Color.appNeutralGray2)

                            Spacer(minLength: 8)

                            if controller.draft.inspectionDateMode == .selectDate {
                                Button {
                                    toggle(.inspection)
                                } label: {
                                    inspectionPill(
                                        AppDateFormatting.longNestDraftDate(
                                            controller.draft.inspectionDate
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                inspectionPill(daysPillText)
                            }
                        }
                        .padding(.horizontal, 10)

                        if controller.draft.inspectionDateMode == .selectDate {
                            if datePickerTarget == .inspection {
                                AddNestInlineDatePicker(
                                    selection: dateBinding(for: .inspection)
                                )
                            }
                        } else {
                            // The number of days is the input; the row above
                            // already shows the date it resolves to, so the
                            // choice is never made blind.
                            AddNestBigNumberField(
                                text: $controller.draft.daysAfterCollection,
                                focus: $isFieldFocused
                            )
                            .onChange(of: controller.draft.daysAfterCollection) { _, _ in
                                controller.updateInspectionDateFromDays()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .containerRelativeFrame(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 21)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissesKeyboardOnTap($isFieldFocused)
        .onAppear {
            // A fresh draft's derived dates are only placeholders until this
            // runs; a draft returning from further in the flow is already
            // correct, and recomputing again here is harmless.
            controller.refreshDerivedDates()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HatcheryPrimaryButton(title: "Save & Preview", action: onPreview)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(Color.white)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var inspectionRowLabel: String {
        controller.draft.inspectionDateMode == .selectDate
            ? "Inspection date will be on"
            : "Inspection date will be in"
    }

    private var daysPillText: String {
        let days = Int(controller.draft.daysAfterCollection) ?? 0
        return days == 1 ? "1 day" : "\(days) days"
    }

    private func inspectionPill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: "#F1F1F1").opacity(0.5), in: Capsule())
    }

    /// The calendar expands under the field it belongs to, so tapping the same
    /// field again closes it and only one can be open at a time.
    private func toggle(_ target: NestDatePickerTarget) {
        withAnimation(.snappy(duration: 0.25)) {
            datePickerTarget = datePickerTarget == target ? nil : target
        }
    }

    private func dateBinding(for target: NestDatePickerTarget) -> Binding<Date> {
        Binding(
            get: {
                let draftValue = switch target {
                case .collection: controller.draft.collectionDate
                case .inspection: controller.draft.inspectionDate
                }
                return AppDateFormatting.parseNestDraftDate(draftValue) ?? .now
            },
            set: { date in
                let formattedDate = AppDateFormatting.nestDraftDateString(date)
                switch target {
                case .collection:
                    controller.draft.collectionDate = formattedDate
                    controller.updateEstimatedHatchDate()
                    // Only one of these two does anything, depending on which
                    // field the user is actually driving in the current
                    // mode -- moving the collection date has to carry
                    // whichever one is live along with it.
                    controller.updateInspectionDateFromDays()
                    controller.updateDaysAfterCollectionFromInspectionDate()
                case .inspection:
                    controller.draft.inspectionDate = formattedDate
                    // The reverse of the "After X days" field driving
                    // inspectionDate: picking a date here has to update the
                    // day count too, or switching modes afterward would
                    // discard what was just picked.
                    controller.updateDaysAfterCollectionFromInspectionDate()
                }
            }
        )
    }
}

/// The calendar expands beneath the field that requested it. Keeping this
/// state local to the egg-information flow prevents the picker from leaking
/// into the other Add Nest screens.
private enum NestDatePickerTarget {
    case collection
    case inspection
}

struct AddNestPreviewView: View {
    @Bindable var controller: NestController
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // This screen's own Figma frame has no step indicator --
                    // just the floating back/close circles (the Accessory Bar
                    // component) above a centered title, unlike steps 1/2.
                    // "Back" reruns the same action as "Edit details" below --
                    // both return to the editable form, so there is no
                    // separate callback to plumb through.
                    VStack(spacing: 12) {
                        Text("Preview Your Nest")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appGreenPrimary)
                            .frame(width: 321, height: 34)

                        Text("Please review the details before saving.")
                            .font(.body)
                            .foregroundStyle(Color.appNeutralGray1)
                            .multilineTextAlignment(.center)
                            .frame(width: 321, height: 22)
                    }
                    // Sized by its own text, not a fixed 100: the title and
                    // subtitle come to 68, so the extra 32 was dead space
                    // between the subtitle and the card below.
                    .frame(width: 321, alignment: .top)
                    .padding(.top, 78)

                    AddNestPreviewCard(
                        nestNumber: controller.draft.nestNumber,
                        eggCount: controller.draft.numberOfEggs,
                        hatchDate: controller.draft.hatchDate,
                        daysLeft: controller.daysUntilHatchDisplay
                    )
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                    AddNestPreviewDetailRow(
                        bucketID: controller.draft.bucketID,
                        section: controller.draft.section,
                        inspectionDate: controller.draft.inspectionDate
                    )
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                    // Only shown once the optional map step has been used;
                    // an empty block would imply the pin was lost.
                    if let latitude = controller.draft.latitude,
                       let longitude = controller.draft.longitude {
                        // The caption labels the card from outside it, matching
                        // the detail row above, which is also captioned in the
                        // page rather than inside its own box.
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nest was found")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))

                            AddNestFoundLocationCard(
                                latitude: latitude,
                                longitude: longitude,
                                address: controller.draft.locationAddress
                            )
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                    }

                    if let errorMessage = controller.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.appRed)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                }
                .containerRelativeFrame(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            AddNestFlowHeader(style: .backAndClose, onBack: onEdit, onClose: onCancel)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                HatcheryPrimaryButton(
                    title: controller.isSaving ? "Saving…" : "Save nest",
                    isDisabled: controller.isSaving,
                    action: onSave
                )

                AddNestPrimaryButton(
                    title: "Edit details",
                    action: onEdit,
                    isSecondary: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.white)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

struct NestRegistrationSuccessView: View {
    let nestNumber: String
    let eggCount: String
    let hatchDate: String
    let temperatureC: Double
    let onViewNest: () -> Void
    let onBackToHatchery: () -> Void

    private var temperatureStatus: NestTemperature.Band {
        NestTemperature.Band(temperatureC: temperatureC)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground(glowColor: temperatureStatus.backgroundGlowColor)

            // TODO: play Resources/success_confetti.lottie here once a
            ScrollView {
                VStack(spacing: 12) {
                    // The animation is itself a check mark, so it stands in
                    // for the glyph rather than playing over it. Under Reduce
                    // Motion it falls back to the static symbol, which is why
                    // the tint is still needed here.
                    //
                    // `.fill` already draws its own circular backing (the
                    // checkmark is a cutout, not a separate white glyph on
                    // top) -- wrapping it in another background circle drew
                    // two, a colored ring around a white disc instead of one
                    // flat colored circle.
                    NestSuccessCheckmark(fallbackTint: temperatureStatus.accentColor)

                    Text("Nest #\(displayNestNumber) registered!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(temperatureStatus.titleColor)
                        .multilineTextAlignment(.center)

                    Text("Monitoring is now active.")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1)
                }
                .padding(.top, 96)
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    AddNestTemperatureCard(
                        temperatureC: temperatureC,
                        accentColor: temperatureStatus.accentColor
                    )

                    HStack(spacing: 12) {
                        AddNestSummaryMetricCard(
                            title: "Estimated hatch",
                            value: AppDateFormatting.longNestDraftDate(hatchDate)
                        )

                        AddNestSummaryMetricCard(title: "Eggs", value: eggCount)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                AddNestPrimaryButton(title: "View nest", action: onViewNest)
                AddNestPrimaryButton(
                    title: "Back to Hatchery",
                    action: onBackToHatchery,
                    isSecondary: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.white)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var displayNestNumber: String {
        let trimmed = nestNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        return Int(trimmed).map(String.init) ?? trimmed
    }
}

// `NestTemperatureStatus` used to live here with its own 24-32°C bounds,
// which disagreed with the nest cards. Both now read `NestTemperature`, whose
// thresholds come from the infobook.
private extension NestTemperature.Band {
    /// The success screen tints its title and glow from the same band, so a
    /// nest that reads hot on its card cannot read healthy on registration.
    var accentColor: Color { tint }

    var titleColor: Color { self == .optimal ? .appGreenPrimary : .black }

    var backgroundGlowColor: Color {
        switch self {
        case .optimal: Color(hex: "#003C22").opacity(0.1)
        case .noData: Color(hex: "#8E8E93").opacity(0.1)
        default: tint.opacity(0.1)
        }
    }
}

#Preview("Add nest identity", traits: .fixedLayout(width: 402, height: 874)) {
    AddNestIdentityView(
        controller: AddNestPreviewFixtures.controller(),
        onSelectSection: { },
        onPinLocation: { },
        onNext: { },
        onCancel: { }
    )
}

#Preview("Add nest egg information", traits: .fixedLayout(width: 402, height: 874)) {
    AddNestEggInformationView(
        controller: AddNestPreviewFixtures.controller(),
        onPreview: { },
        onCancel: { }
    )
}

#Preview("Add nest preview", traits: .fixedLayout(width: 402, height: 874)) {
    AddNestPreviewView(
        controller: AddNestPreviewFixtures.controller(),
        onEdit: { },
        onCancel: { },
        onSave: { }
    )
}

#Preview("Nest registered: normal", traits: .fixedLayout(width: 402, height: 874)) {
    NestRegistrationSuccessView(
        nestNumber: "055",
        eggCount: "100",
        hatchDate: "03.03.2026",
        temperatureC: 30,
        onViewNest: { },
        onBackToHatchery: { }
    )
}

#Preview("Nest registered: hot", traits: .fixedLayout(width: 402, height: 874)) {
    NestRegistrationSuccessView(
        nestNumber: "055",
        eggCount: "100",
        hatchDate: "03.03.2026",
        temperatureC: 34,
        onViewNest: { },
        onBackToHatchery: { }
    )
}

#Preview("Nest registered: cold", traits: .fixedLayout(width: 402, height: 874)) {
    NestRegistrationSuccessView(
        nestNumber: "055",
        eggCount: "100",
        hatchDate: "03.03.2026",
        temperatureC: 22,
        onViewNest: { },
        onBackToHatchery: { }
    )
}

@MainActor
private enum AddNestPreviewFixtures {
    static func controller() -> NestController {
        NestController(
            hatcheryID: UUID(),
            nestService: NestService(repository: InMemoryNestRepository())
        )
    }

    /// Matches the 3×4 grid `HatcheryGridPreviewView`'s own preview builds,
    /// so a section id like "B1" resolves the same way in both.
    static func grid() -> HatcheryGrid {
        HatcheryGrid(
            rows: 3,
            columns: 4,
            sections: (0..<3).flatMap { row in
                (0..<4).map { column in
                    HatcherySection(
                        id: "\(HatcheryGrid.columnLabel(column))\(row + 1)",
                        row: row,
                        column: column,
                        widthM: 2,
                        heightM: 2,
                        boundary: .fullImage.sectionBoundary(
                            row: row,
                            column: column,
                            rowCount: 3,
                            columnCount: 4
                        )
                    )
                }
            }
        )
    }
}

#Preview("Add nest: pick section", traits: .fixedLayout(width: 402, height: 874)) {
    NestSectionPickerView(
        controller: AddNestPreviewFixtures.controller(),
        grid: AddNestPreviewFixtures.grid(),
        mapImage: UIImage(named: "HatcherySamplePhoto") ?? UIImage(),
        usesMockMapCrop: true,
        // Left nil deliberately: the "—" / "No data yet" states are what a
        // brand-new hatchery with no readings or nests yet actually looks
        // like, which is the more useful case to preview here.
        dashboard: nil,
        onCancel: { },
        onConfirm: { }
    )
}
