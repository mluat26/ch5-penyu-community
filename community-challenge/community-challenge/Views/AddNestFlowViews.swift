import CoreLocation
import MapKit
import SwiftUI
import UIKit

extension View {
    /// Dismisses the keyboard when anything outside a field is tapped.
    ///
    /// The number pads in this flow have no Return key, so without this there
    /// is no way to put the keyboard away at all. Added as a *simultaneous*
    /// gesture so it runs alongside buttons underneath rather than swallowing
    /// their taps.
    ///
    /// Takes the screen's own `@FocusState` rather than reaching for
    /// `UIResponder.resignFirstResponder()` broadcast to the whole app. That
    /// call goes to whatever the current first responder is, unscoped -- on a
    /// screen that also hosts a `.graphical` `DatePicker` (a UIKit
    /// `UICalendarView` under the hood), firing it on every tap, including
    /// taps on the calendar's own day cells, is exactly the kind of
    /// interference that makes an otherwise-working control feel broken.
    /// Clearing a `FocusState` only ever affects the fields actually bound to
    /// it, so it cannot touch anything else on screen.
    func dismissesKeyboardOnTap(_ isFieldFocused: FocusState<Bool>.Binding) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                isFieldFocused.wrappedValue = false
            }
        )
    }
}

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
            // once that integration exists. A `simultaneousGesture` so it
            // doesn't compete with the close button's own tap above it.
            .simultaneousGesture(TapGesture().onEnded(onContinue))

            AddNestFlowHeader(style: .closeOnly, onBack: nil, onClose: onCancel)
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

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AddNestFlowTopHeader(currentStep: 1, onClose: onCancel)

                    VStack(alignment: .leading, spacing: 16) {
                        AddNestSectionTitle(title: "Nest identity")

                        // Two short identifiers read as one line in the field,
                        // so they share a row rather than stacking.
                        HStack(alignment: .top, spacing: 10) {
                            AddNestLabeledTextField(
                                label: "Bucket ID",
                                text: $controller.draft.bucketID,
                                isMuted: true,
                                controlHeight: 48,
                                cornerRadius: 16,
                                focus: $isFieldFocused
                            )

                            AddNestLabeledTextField(
                                label: "Nest Number",
                                text: $controller.draft.nestNumber,
                                isMuted: true,
                                controlHeight: 48,
                                cornerRadius: 16,
                                keyboardType: .numberPad,
                                focus: $isFieldFocused
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
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissesKeyboardOnTap($isFieldFocused)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AddNestPrimaryButton(title: "Next") {
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
            AddNestPrimaryButton(title: "Save & Preview", action: onPreview)
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
                    // Outside the sized frame, not inside it: padding applied
                    // before `.frame(height: 100)` pushes the content down
                    // within that box instead of moving the box itself, and
                    // the content had nowhere to go but overflow past its own
                    // bottom edge into the card below it.
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
                AddNestPrimaryButton(
                    title: controller.isSaving ? "Saving…" : "Save nest",
                    action: onSave,
                    isDisabled: controller.isSaving
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

    private var temperatureStatus: NestTemperatureStatus {
        NestTemperatureStatus(temperatureC: temperatureC)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground(glowColor: temperatureStatus.backgroundGlowColor)

            // TODO: play Resources/success_confetti.lottie here once a
            // Lottie-rendering package is added -- see conversation. A static
            // image was tried and removed; the current design has no static
            // ribbon graphic at rest, only a one-time animation on arrival.

            ScrollView {
                VStack(spacing: 12) {
                    // `.fill` already draws its own circular backing (the
                    // checkmark is a cutout, not a separate white glyph on
                    // top) -- wrapping it in another background circle drew
                    // two, a colored ring around a white disc instead of one
                    // flat colored circle.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(temperatureStatus.accentColor)
                        .accessibilityHidden(true)

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

private enum AddNestHeaderStyle {
    case closeOnly
    case backAndClose
}

private struct AddNestFlowHeader: View {
    let style: AddNestHeaderStyle
    let onBack: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack {
            switch style {
            case .closeOnly:
                headerButton(systemImage: "xmark", label: "Cancel", action: onClose)
            case .backAndClose:
                if let onBack {
                    headerButton(systemImage: "chevron.backward", label: "Back", action: onBack)
                }
            }

            Spacer(minLength: 0)

            if style == .backAndClose {
                headerButton(systemImage: "xmark", label: "Cancel", action: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private func headerButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appNeutralBlack)
                .frame(width: 36, height: 36)
                .frame(width: 48, height: 48)
                .glassEffect()
                .frame(width: 72, height: 48)
                // `.plain` hit-tests rendered content, so without this the
                // 12 pt either side of the glass circle is dead -- and that is
                // the screen-edge side of both buttons, where a thumb lands.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 48)
        .accessibilityLabel(label)
    }
}

/// Shared top header for every screen in the Add Nest flow: title, subtitle
/// and a close button on one row, then the full-width step indicator below.
/// One definition so every step reads identically save for which step is lit.
private struct AddNestFlowTopHeader: View {
    let currentStep: Int
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Create new nest")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(0.38)
                        .foregroundStyle(Color.appGreenPrimary)

                    Text("Let’s register a new turtle nest\nto start monitoring its journey.")
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray1.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appNeutralBlack)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
            .padding(.horizontal, 16)

            AddNestProgressIndicator(currentStep: currentStep, compact: false)
                .padding(.horizontal, 22)
                .padding(.top, 24)
        }
    }
}

private struct AddNestFlowBackground: View {
    var glowColor = Color(
        red: 254.0 / 255.0,
        green: 246.0 / 255.0,
        blue: 237.0 / 255.0
    )

    var body: some View {
        Color.white
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(glowColor)
                    .frame(width: 621, height: 621)
                    .blur(radius: 50)
                    .offset(x: -110, y: -378)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container, edges: .all)
    }
}

private struct AddNestProgressIndicator: View {
    let currentStep: Int
    let compact: Bool

    private var circleSize: CGFloat { compact ? 24 : 28 }
    private var itemSpacing: CGFloat { compact ? 6 : 6 }
    private var connectorHeight: CGFloat { compact ? 0.6 : 1 }
    private var textFont: Font { .system(size: 9, weight: .medium) }

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(1...3, id: \.self) { step in
                stepCircle(step)

                if step < 3 {
                    // The rail stretches to whatever width it is given rather
                    // than a fixed span, so the row lines up with the fields
                    // below it on every screen size.
                    Rectangle()
                        .fill(Color(hex: "#AEAEB2"))
                        .frame(maxWidth: .infinity)
                        .frame(height: connectorHeight)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep) of 3")
    }

    private func stepCircle(_ step: Int) -> some View {
        let isCurrent = step == currentStep

        return ZStack {
            Circle()
                .fill(isCurrent ? Color.appGreenPrimary : .white)
                .overlay {
                    Circle()
                        .stroke(isCurrent ? Color.appGreenPrimary : Color(hex: "#AEAEB2"), lineWidth: 1)
                }

            Text("\(step)")
                .font(textFont)
                .fontWeight(.medium)
                .foregroundStyle(isCurrent ? Color.white : Color(hex: "#AEAEB2"))
        }
        .frame(width: circleSize, height: circleSize)
    }
}

private struct AddNestSectionTitle: View {
    /// Omitted where the design shows a bare heading. The egg-information
    /// screen still numbers its two sections, so the prefix stays available
    /// rather than being deleted outright.
    var number: Int? = nil
    let title: String

    var body: some View {
        Text(number.map { "\($0). \(title)" } ?? title)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appGreenPrimary)
    }
}

/// A tappable row that opens a further step: an icon, a title over a hint, and
/// a trailing chevron.
///
/// Used by both *Section* and *Location* on the identity screen, which are
/// visually identical, so the shape lives in one place.
private struct AddNestDisclosureRow: View {
    /// Optional: a resolved address needs the full width, so the pinned
    /// location row drops its icon rather than truncating the street.
    let systemImage: String?
    /// A `Text` rather than a `String` so the filled-in part can be emphasized
    /// inline, as in "Selected **section B1**".
    let title: Text
    let subtitle: String
    /// Tints the row once a value has been chosen. Without it the row looks
    /// identical before and after, and the only way to tell was to read it.
    let isSelected: Bool
    var titleLineLimit: Int = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title)
                        .foregroundStyle(Color.appGreenPrimary)
                        .frame(width: 33, height: 34)
                }

                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.body)
                        .foregroundStyle(Color.appNeutralGray2)
                        .lineLimit(titleLineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#AEAEB2"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appNeutralGray2)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            // Grows with a wrapped address instead of clipping it.
            .frame(maxWidth: .infinity, minHeight: 77, alignment: .leading)
            .background(
                isSelected
                    ? Color.appGreenPrimary.opacity(0.12)
                    : Color(hex: "#E0E0E0").opacity(0.2),
                in: RoundedRectangle(cornerRadius: 24)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(subtitle)
    }
}

private struct AddNestLabeledTextField: View {
    let label: String
    @Binding var text: String
    var isMuted = false
    var controlHeight: CGFloat = 42
    var cornerRadius: CGFloat = 10
    var keyboardType: UIKeyboardType = .default
    /// The screen's own focus flag. Binding every field to the same boolean
    /// is enough to know "is any field active" -- which field specifically
    /// doesn't matter for dismissing the keyboard on an outside tap.
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appNeutralGray2)

            Group {
                if let focus {
                    TextField(label, text: $text)
                        .focused(focus)
                } else {
                    TextField(label, text: $text)
                }
            }
                .font(isMuted ? .subheadline : .body)
                .foregroundStyle(.black)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight, alignment: .leading)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isMuted ? Color(hex: "#FFFBF7") : Color(hex: "#EBEBEB"), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldBackground: Color {
        isMuted ? Color(hex: "#787878").opacity(0.2) : Color.white
    }
}

/// A large centered numeric readout that doubles as its own text field: the
/// egg count and the "after X days" count share this exact look in the
/// design, so it is one component used twice rather than two near-identical
/// fields.
private struct AddNestBigNumberField: View {
    /// Omitted for the days field, which is already introduced by the row
    /// above it ("Inspection date will be in ...").
    var label: String? = nil
    @Binding var text: String
    /// See `AddNestLabeledTextField.focus`.
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        VStack(spacing: 10) {
            if let label {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appGreenPrimary)
            }

            Group {
                if let focus {
                    TextField("", text: $text)
                        .focused(focus)
                } else {
                    TextField("", text: $text)
                }
            }
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.86)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .foregroundStyle(.black)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    Color(hex: "#F1F1F1").opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 24)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AddNestDateField: View {
    let label: String
    let value: String
    var controlHeight: CGFloat = 42
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appNeutralGray2)

            Button(action: action) {
                HStack {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(.black)

                    Spacer(minLength: 0)

                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(Color.appNeutralGray2)
                        .frame(width: 27, height: 28)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddNestTimelineDateBlock: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        AddNestDateField(
            label: label,
            value: value,
            controlHeight: 50,
            action: action
        )
        .frame(width: 341)
        .frame(width: 370, height: 90)
    }
}

/// A real segmented control -- one continuous track, the active segment
/// carrying a sliding white highlight -- rather than two separate buttons
/// with a gap between them.
private struct AddNestInspectionModeControl: View {
    let mode: NestInspectionDateMode
    let onSelect: (NestInspectionDateMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(.selectDate, title: "Select date", systemImage: "calendar")
            segment(.afterCollectionDays, title: "After X days", systemImage: "calendar.badge.plus")
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color(hex: "#F1F1F1").opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func segment(
        _ value: NestInspectionDateMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = mode == value

        return Button {
            onSelect(value)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.callout)
                Text(title)
                    .font(.callout)
            }
            .foregroundStyle(Color.appNeutralGray2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected ? Color.white : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AddNestPreviewCard: View {
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
                    "* \(Text("Auto").foregroundStyle(Color.appGreenPrimary).fontWeight(.medium))"
                )
                .font(.caption2)
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(hex: "#939393").opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The identifiers that are not part of the headline summary: which bucket the
/// clutch is in, which grid cell it went to, and when someone is due to look at
/// it. Confirming these is the point of this screen, so they are shown rather
/// than trusted.
private struct AddNestPreviewDetailRow: View {
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
private struct AddNestFoundLocationCard: View {
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

private struct AddNestTemperatureCard: View {
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

private struct AddNestSummaryMetricCard: View {
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

/// Not private: the location picker lives in its own file and uses the same
/// primary action button.
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

private enum NestDatePickerTarget {
    case collection
    case inspection

    var title: String {
        switch self {
        case .collection: "Egg collection date"
        case .inspection: "Egg inspection date"
        }
    }
}

/// The calendar opens in place under its field rather than in a sheet, so the
/// dates being related to each other stays visible while one is picked.
private struct AddNestInlineDatePicker: View {
    @Binding var selection: Date

    var body: some View {
        DatePicker("", selection: $selection, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Color.appGreenPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 370)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct NestSectionPickerView: View {
    @Bindable var controller: NestController
    let grid: HatcheryGrid
    let mapImage: UIImage
    let usesMockMapCrop: Bool
    let dashboard: HatcheryDashboard?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var pendingSection: String

    init(
        controller: NestController,
        grid: HatcheryGrid,
        mapImage: UIImage,
        usesMockMapCrop: Bool,
        dashboard: HatcheryDashboard?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.controller = controller
        self.grid = grid
        self.mapImage = mapImage
        self.usesMockMapCrop = usesMockMapCrop
        self.dashboard = dashboard
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _pendingSection = State(initialValue: controller.draft.section)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Presented as a sheet over the form, so it carries its own bar
            // rather than a navigation bar: the choice is confirmed or
            // abandoned here and does not become a step in the flow's history.
            sheetBar

            ScrollView {
                VStack(spacing: 10) {
                    infoCard

                    NestSectionMapView(
                        image: mapImage,
                        usesMockCrop: usesMockMapCrop,
                        grid: grid,
                        selectedSectionID: pendingSection,
                        onSelect: { section in
                            guard section.isActive else { return }
                            pendingSection = section.id
                        }
                    )

                    selectionSummary
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(.white)
        .preferredColorScheme(.light)
    }

    private var sheetBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appNeutralBlack)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel section selection")

            Spacer()

            Text("Select the section")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appNeutralBlack)

            Spacer()

            Button(action: confirmSelection) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        pendingSection.isEmpty
                            ? Color.appNeutralGray3
                            : Color.appGreenPrimary
                    )
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(pendingSection.isEmpty)
            .accessibilityLabel("Confirm section selection")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white)
    }

    private var infoCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "info.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.appGreenPrimary)

            VStack(alignment: .leading, spacing: 0) {
                Text("Place it on the map")
                    .font(.body)
                    .foregroundStyle(Color.appNeutralGray2)

                Text("Choose the grid where this nest will be registered.")
                    .font(.footnote)
                    .foregroundStyle(Color(hex: "#AEAEB2"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 370, minHeight: 78, alignment: .leading)
        .background(Color.appGreenPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectionSummary: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "graph.3d")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.appGreenPrimary)
                    .frame(width: 62, height: 59)

                Text(selectedMapSection.map { "Section \($0.id)" } ?? "Choose a section")
                    .font(.headline)
                    .foregroundStyle(.black)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .frame(width: 370, height: 59)
            .clipped()

            Color.clear
                .frame(width: 350, height: 0)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                        .offset(y: -1)
                }

            HStack(spacing: 10) {
                selectionMetric(
                    title: "Average temperature",
                    value: temperatureText,
                    unit: temperatureText == "—" ? nil : "°C",
                    color: Color(hex: "#0C7C4D"),
                    valueWeight: .bold,
                    width: 177
                )

                selectionMetric(
                    title: "Registered nests",
                    value: selectedSectionDashboard.map { String($0.nestCount) } ?? "—",
                    unit: nil,
                    color: .black,
                    valueWeight: .semibold,
                    width: 168
                )

                Spacer(minLength: 0)
            }
            .frame(width: 370, height: 85, alignment: .leading)
        }
        .frame(width: 370)
    }

    private func selectionMetric(
        title: String,
        value: String,
        unit: String?,
        color: Color,
        valueWeight: Font.Weight,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .opacity(0.8)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: 16, alignment: .top)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                Text(value)
                    .font(.system(size: 20, weight: valueWeight))

                if let unit {
                    Text(unit)
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: 25, alignment: .top)
        }
        .padding(16)
        .frame(width: width, height: 85)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 10)
    }

    private var selectedMapSection: HatcherySection? {
        grid.sections.first { $0.id == pendingSection }
    }

    private var selectedSectionDashboard: HatcherySectionDashboard? {
        guard let selectedMapSection else { return nil }
        return dashboard?.section(row: selectedMapSection.row, column: selectedMapSection.column)
    }

    private var temperatureText: String {
        guard let temperature = selectedSectionDashboard?.averageTemperatureC else { return "—" }
        return temperature.formatted(.number.precision(.fractionLength(1)))
    }

    private func confirmSelection() {
        guard let selection = selectedMapSection, selection.isActive else { return }
        controller.draft.section = selection.id
        controller.draft.sectionRow = selection.row
        controller.draft.sectionColumn = selection.column
        onConfirm()
    }
}

private struct NestSectionMapView: View {
    let image: UIImage
    let usesMockCrop: Bool
    let grid: HatcheryGrid
    let selectedSectionID: String
    let onSelect: (HatcherySection) -> Void

    private var rows: Int { max(grid.rows, 1) }
    private var columns: Int { max(grid.columns, 1) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Color.clear
                    .frame(width: 9, height: 16)

                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(column < grid.columnLabels.count
                             ? grid.columnLabels[column]
                             : HatcheryGrid.columnLabel(column))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(row < grid.rowLabels.count ? grid.rowLabels[row] : "\(row + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxWidth: .infinity)

                        if row < rows - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 40)
                .frame(width: 9, height: 279)

                GeometryReader { geometry in
                    ZStack {
                        HatcherySetupImage(image: image, usesMockCrop: usesMockCrop)

                        VStack(spacing: 2) {
                            ForEach(0..<rows, id: \.self) { row in
                                HStack(spacing: 2) {
                                    ForEach(0..<columns, id: \.self) { column in
                                        sectionCell(row: row, column: column)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .frame(height: 279)
            }
        }
        .frame(maxWidth: 370)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hatchery grid, \(columns) columns and \(rows) rows")
    }

    @ViewBuilder
    private func sectionCell(row: Int, column: Int) -> some View {
        if let section = grid.sections.first(where: { $0.row == row && $0.column == column }) {
            Button {
                onSelect(section)
            } label: {
                ZStack {
                    sectionColor(for: section)

                    if section.id == selectedSectionID {
                        Text(section.id)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                            .frame(width: 35, height: 35)
                            .background(.white, in: Circle())
                            .padding(4)
                            .background(.white.opacity(0.24), in: Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!section.isActive)
            .accessibilityLabel("Section \(section.id)")
            .accessibilityValue(section.id == selectedSectionID ? "Selected" : "")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black.opacity(0.12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sectionColor(for section: HatcherySection) -> Color {
        guard section.isActive else { return .black.opacity(0.14) }
        return Color(hex: "#003C22").opacity(section.id == selectedSectionID ? 0.7 : 0.3)
    }
}

private enum NestTemperatureStatus {
    case normal
    case hot
    case cold

    init(temperatureC: Double) {
        if temperatureC > 32 {
            self = .hot
        } else if temperatureC < 24 {
            self = .cold
        } else {
            self = .normal
        }
    }

    var accentColor: Color {
        switch self {
        case .normal: .appGreenPrimary
        case .hot: Color(hex: "#FF383C")
        case .cold: Color(hex: "#00C3D0")
        }
    }

    var titleColor: Color {
        self == .normal ? .appGreenPrimary : .black
    }

    var backgroundGlowColor: Color {
        switch self {
        case .normal: Color(hex: "#003C22").opacity(0.1)
        case .hot: Color(hex: "#FF383C").opacity(0.1)
        case .cold: Color(hex: "#00C3D0").opacity(0.1)
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
