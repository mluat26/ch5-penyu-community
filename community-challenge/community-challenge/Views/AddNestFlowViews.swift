import SwiftUI
import UIKit

struct AddNestIdentityView: View {
    @Bindable var controller: NestController
    let onSelectSection: () -> Void
    let onNext: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Text("Create new nest")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appGreenPrimary)
                            .frame(width: 321, height: 34)

                        Text("Let’s register a new turtle nest\nto start monitoring its journey.")
                            .font(.body)
                            .foregroundStyle(Color.appNeutralGray1)
                            .multilineTextAlignment(.center)
                            .frame(width: 321, height: 44)
                    }
                    .frame(width: 321, height: 90)

                    AddNestProgressIndicator(currentStep: 1, compact: false)
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        AddNestSectionTitle(number: 1, title: "Nest identity")

                        AddNestLabeledTextField(
                            label: "QR / Bucket ID",
                            text: $controller.draft.bucketID,
                            isMuted: true
                        )
                        .padding(10)
                        .frame(height: 92)

                        AddNestLabeledTextField(
                            label: "Nest Number",
                            text: $controller.draft.nestNumber,
                            isMuted: true,
                            keyboardType: .numberPad
                        )
                        .padding(10)
                        .frame(height: 92)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Section")
                                .font(.subheadline)
                                .foregroundStyle(Color.appNeutralGray2)

                            Button(action: onSelectSection) {
                                HStack(spacing: 9) {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.title)
                                        .foregroundStyle(Color.appGreenPrimary)
                                        .frame(width: 33, height: 34)

                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(sectionTitle)
                                            .font(.body)
                                            .foregroundStyle(Color.appNeutralGray2)
                                            .lineLimit(1)

                                        Text(sectionSubtitle)
                                            .font(.footnote)
                                            .foregroundStyle(Color(hex: "#AEAEB2"))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                    .frame(width: 253, alignment: .leading)

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.right")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.appNeutralGray2)
                                        .frame(width: 17, height: 20)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 77, maxHeight: 77, alignment: .leading)
                                .background(Color(hex: "#F1F1F1").opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityHint("Opens a grid to choose the nest location")
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .frame(height: 117, alignment: .top)

                        if let errorMessage = controller.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.appRed)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .frame(height: 443, alignment: .top)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .containerRelativeFrame(.horizontal)
                .padding(.top, 88)
            }
            .scrollIndicators(.hidden)

            AddNestFlowHeader(style: .closeOnly, onBack: nil, onClose: onCancel)
        }
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

    private var sectionTitle: String {
        controller.draft.section.isEmpty
            ? "Select section on the map"
            : "Section \(controller.draft.section)"
    }

    private var sectionSubtitle: String {
        controller.draft.section.isEmpty
            ? "Tap a grid cell to choose the nest location"
            : "Tap to change the nest location"
    }
}

struct AddNestEggInformationView: View {
    @Bindable var controller: NestController
    let onBack: () -> Void
    let onPreview: () -> Void
    let onCancel: () -> Void

    @State private var datePickerTarget: NestDatePickerTarget?

    var body: some View {
        ZStack(alignment: .top) {
            AddNestFlowBackground()

            ScrollView {
                VStack(spacing: 0) {
                    AddNestProgressIndicator(currentStep: 2, compact: true)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .center, spacing: 0) {
                        AddNestSectionTitle(number: 2, title: "Egg information")
                            .frame(width: 370, alignment: .leading)

                        AddNestLabeledTextField(
                            label: "Number of eggs",
                            text: $controller.draft.numberOfEggs,
                            isEmphasized: true,
                            controlHeight: 44,
                            keyboardType: .numberPad
                        )
                        .padding(10)
                        .frame(width: 370, height: 94)
                        .padding(.top, 10)
                    }
                    .frame(width: 402)
                    .offset(x: -1)
                    .padding(.top, 33)

                    VStack(alignment: .center, spacing: 10) {
                        AddNestSectionTitle(number: 3, title: "Timeline")
                            .frame(width: 370, alignment: .leading)

                        AddNestTimelineDateBlock(
                            label: "Egg collection date",
                            value: controller.draft.collectionDate
                        ) {
                            datePickerTarget = .collection
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Egg inspection date")
                                .font(.subheadline)
                                .foregroundStyle(Color.appNeutralGray2)

                            HStack(spacing: 10) {
                                AddNestInspectionModeButton(
                                    title: "Select date",
                                    systemImage: "calendar",
                                    isSelected: controller.draft.inspectionDateMode == .selectDate
                                ) {
                                    controller.draft.inspectionDateMode = .selectDate
                                }

                                AddNestInspectionModeButton(
                                    title: "After X days",
                                    systemImage: "calendar.badge.plus",
                                    isSelected: controller.draft.inspectionDateMode == .afterCollectionDays
                                ) {
                                    controller.draft.inspectionDateMode = .afterCollectionDays
                                    controller.updateEstimatedHatchDate()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(10)
                        .frame(width: 370, height: 100, alignment: .topLeading)

                        if controller.draft.inspectionDateMode == .selectDate {
                            AddNestTimelineDateBlock(
                                label: "Inspection date",
                                value: controller.draft.inspectionDate
                            ) {
                                datePickerTarget = .inspection
                            }
                        } else {
                            AddNestTimelineDateBlock(
                                label: "Days after collection",
                                value: controller.draft.collectionDate
                            ) {
                                datePickerTarget = .collection
                            }
                        }

                        AddNestEstimatedHatchCard(date: controller.draft.hatchDate)
                            .frame(width: 370, height: 93)
                    }
                    .frame(width: 402)
                    .offset(x: 2)
                    .padding(.top, 28)
                }
                .containerRelativeFrame(.horizontal)
                .padding(.top, 32)
                .padding(.bottom, 21)
            }
            .scrollIndicators(.hidden)

            AddNestFlowHeader(style: .backAndClose, onBack: onBack, onClose: onCancel)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AddNestPrimaryButton(title: "Save & Preview", action: onPreview)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(Color.white)
        }
        .sheet(item: $datePickerTarget) { target in
            AddNestDatePickerSheet(
                title: target.title,
                selection: dateBinding(for: target)
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
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
                case .inspection:
                    controller.draft.inspectionDate = formattedDate
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
                    AddNestProgressIndicator(currentStep: 3, compact: true)
                        .frame(maxWidth: .infinity)

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
                    .padding(.top, 32)
                    .frame(width: 321, height: 100, alignment: .top)

                    AddNestPreviewCard(
                        nestNumber: controller.draft.nestNumber,
                        eggCount: controller.draft.numberOfEggs,
                        hatchDate: controller.draft.hatchDate,
                        daysLeft: controller.draft.daysLeftDisplay
                    )
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                    Image("AddNestTurtle")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 185, height: 134)
                        .clipped()
                        .offset(x: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 209)

                    if let errorMessage = controller.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.appRed)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }
                }
                .containerRelativeFrame(.horizontal)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            AddNestFlowHeader(style: .closeOnly, onBack: nil, onClose: onCancel)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                AddNestPrimaryButton(
                    title: controller.isSaving ? "Saving…" : "Save nest",
                    action: onSave,
                    isDisabled: controller.isSaving
                )

                AddNestTextAction(title: "Edit details", action: onEdit)
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
        ZStack {
            AddNestFlowBackground(glowColor: temperatureStatus.backgroundGlowColor)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50, weight: .regular))
                            .foregroundStyle(temperatureStatus.accentColor.opacity(0.5))
                            .frame(width: 59, height: 41)
                            .accessibilityHidden(true)
                            .offset(x: 131)

                        Text("Nest #\(displayNestNumber) \nregistered!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(temperatureStatus.titleColor)
                            .multilineTextAlignment(.center)
                            .frame(width: 321, height: 82, alignment: .top)
                            .offset(y: 53)

                        Text("Monitoring is now active.")
                            .font(.body)
                            .foregroundStyle(Color.appNeutralGray1)
                            .frame(width: 321, height: 22)
                            .offset(y: 147)
                    }
                    .frame(width: 321, height: 169, alignment: .topLeading)
                    .offset(x: 41, y: 158)

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
                    .frame(width: 370, height: 307, alignment: .top)
                    .offset(x: 23, y: 376)
                }
                .frame(width: 402, height: 683, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                AddNestPrimaryButton(title: "View nest", action: onViewNest)
                AddNestTextAction(title: "Back to Hatchery", action: onBackToHatchery)
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
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 48)
        .accessibilityLabel(label)
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

    private var circleSize: CGFloat { compact ? 24 : 40 }
    private var connectorWidth: CGFloat { compact ? 48.6 : 81 }
    private var itemSpacing: CGFloat { compact ? 6 : 10 }
    private var connectorHeight: CGFloat { compact ? 0.6 : 1 }
    private var textFont: Font { .system(size: compact ? 9 : 15, weight: .medium) }

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(1...3, id: \.self) { step in
                stepCircle(step)

                if step < 3 {
                    Rectangle()
                        .fill(Color(hex: "#AEAEB2"))
                        .frame(width: connectorWidth, height: connectorHeight)
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
    let number: Int
    let title: String

    var body: some View {
        Text("\(number). \(title)")
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appGreenPrimary)
    }
}

private struct AddNestLabeledTextField: View {
    let label: String
    @Binding var text: String
    var isMuted = false
    var isEmphasized = false
    var controlHeight: CGFloat = 42
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appNeutralGray2)

            TextField(label, text: $text)
                .font(fieldFont)
                .foregroundStyle(.black)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight, alignment: .leading)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isMuted ? Color(hex: "#FFFBF7") : Color(hex: "#EBEBEB"), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldBackground: Color {
        if isMuted { return Color(hex: "#787878").opacity(0.2) }
        if isEmphasized { return Color(hex: "#F1F1F1").opacity(0.5) }
        return Color.white
    }

    private var fieldFont: Font {
        if isEmphasized { return .body.weight(.semibold) }
        return isMuted ? .subheadline : .body
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

private struct AddNestInspectionModeButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: systemImage == "calendar.badge.plus" ? 8 : 5) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 27, height: 28)
                Text(title)
                    .font(.callout)
            }
            .foregroundStyle(Color.appNeutralGray2)
            .frame(width: 160, height: 50)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        isSelected ? Color.appGreenPrimary.opacity(0.1) : .white
    }

    private var borderColor: Color {
        isSelected ? Color.appGreenPrimary.opacity(0.5) : Color(hex: "#EBEBEB")
    }
}

private struct AddNestEstimatedHatchCard: View {
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Estimated hatch date")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appGreenPrimary)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 22, height: 24)

                    Text("Auto")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .frame(width: 30, height: 18)
                }
                .foregroundStyle(Color.appGreenPrimary)
                .frame(width: 52, height: 24)
                .offset(y: -2)
            }
            .padding(.horizontal, 10)
            .frame(height: 20)

            HStack {
                Text(date)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(height: 48, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 93, maxHeight: 93, alignment: .topLeading)
        .background(Color.appGreenPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AddNestPreviewCard: View {
    let nestNumber: String
    let eggCount: String
    let hatchDate: String
    let daysLeft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nest #\(nestNumber.isEmpty ? "—" : nestNumber)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.black)
                .padding(.leading, 10)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 39, alignment: .topLeading)

            HStack(spacing: 12) {
                AddNestPreviewMetric(
                    value: eggCount,
                    label: "Eggs",
                    valueStyle: .eggCount
                )
                .frame(width: 108)

                AddNestPreviewMetric(
                    value: hatchDate,
                    label: "Ets. hatch",
                    systemImage: "sparkles",
                    valueStyle: .date
                )
                .frame(width: 112)

                AddNestPreviewMetric(
                    value: daysLeft,
                    label: "Days left",
                    systemImage: "hourglass",
                    valueStyle: .daysLeft
                )
            }
            .frame(maxWidth: .infinity, minHeight: 83)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, minHeight: 139, maxHeight: 139, alignment: .topLeading)
        .background(Color.appGreenPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AddNestPreviewMetric: View {
    let value: String
    let label: String
    var systemImage: String?
    let valueStyle: ValueStyle

    enum ValueStyle: Equatable {
        case eggCount
        case date
        case daysLeft

        var font: Font {
            switch self {
            case .eggCount: .system(size: 20, weight: .bold)
            case .date, .daysLeft: .title3.weight(.semibold)
            }
        }

        var color: Color {
            switch self {
            case .eggCount: .appNeutralGray2
            case .date, .daysLeft: .appNeutralGray2
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 16)

            Text(value)
                .font(valueStyle.font)
                .foregroundStyle(valueStyle.color)
                .lineLimit(1)
                .minimumScaleFactor(valueStyle == .date ? 1 : 0.55)
                .fixedSize(horizontal: valueStyle == .date, vertical: false)
                .frame(height: 25)

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.appGreenPrimary)
                }
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(Color(hex: "#8E8E93"))
            .opacity(0.8)
            .lineLimit(1)
            .frame(height: 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 10)
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

private struct AddNestPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: "#FAF8F4"))
                .frame(maxWidth: .infinity, minHeight: 55)
        }
        .buttonStyle(.plain)
        .background(Color.appGreenPrimary, in: RoundedRectangle(cornerRadius: 26))
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }
}

private struct AddNestTextAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appGreenPrimary)
                .frame(maxWidth: .infinity, minHeight: 55)
        }
        .buttonStyle(.plain)
    }
}

private enum NestDatePickerTarget: Identifiable {
    case collection
    case inspection

    var id: Self { self }

    var title: String {
        switch self {
        case .collection: "Egg collection date"
        case .inspection: "Egg inspection date"
        }
    }
}

private struct AddNestDatePickerSheet: View {
    let title: String
    @Binding var selection: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                }
        }
        .presentationDetents([.medium])
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
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(.white)
        .navigationTitle("Place the nest")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel section selection")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: confirmSelection) {
                    Image(systemName: "checkmark")
                }
                .disabled(pendingSection.isEmpty)
                .accessibilityLabel("Confirm section selection")
            }
        }
        .preferredColorScheme(.light)
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
        onNext: { },
        onCancel: { }
    )
}

#Preview("Add nest egg information", traits: .fixedLayout(width: 402, height: 874)) {
    AddNestEggInformationView(
        controller: AddNestPreviewFixtures.controller(),
        onBack: { },
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
}
