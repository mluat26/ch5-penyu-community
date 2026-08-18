import SwiftUI
import UIKit

/// Reusable fields and chrome shared by the Add Nest flow screens.

enum AddNestHeaderStyle {
    case closeOnly
    case backAndClose
}

struct AddNestFlowHeader: View {
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
struct AddNestFlowTopHeader: View {
    let currentStep: Int
    let onClose: () -> Void
    /// Passed to the step indicator, which offers only the steps already
    /// behind this one.
    var onSelectStep: ((Int) -> Void)? = nil

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

            AddNestProgressIndicator(
                currentStep: currentStep,
                compact: false,
                onSelectStep: onSelectStep
            )
                .padding(.horizontal, 22)
                .padding(.top, 24)
        }
    }
}

struct AddNestFlowBackground: View {
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

struct AddNestProgressIndicator: View {
    let currentStep: Int
    let compact: Bool
    /// Supplied where an earlier step can be returned to. Steps at or ahead of
    /// the current one are never offered: nothing has been filled in there yet,
    /// so there is nothing to go back to.
    var onSelectStep: ((Int) -> Void)? = nil

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
        // The circles are only their own elements once they can be tapped;
        // otherwise the row reads as one label, as it did before.
        .accessibilityElement(children: onSelectStep == nil ? .ignore : .contain)
        .accessibilityLabel("Step \(currentStep) of 3")
    }

    @ViewBuilder
    private func stepCircle(_ step: Int) -> some View {
        if step < currentStep, let onSelectStep {
            Button { onSelectStep(step) } label: {
                stepCircleBody(step)
                    // `.plain` hit-tests rendered content, and the circle is
                    // the only thing drawn.
                    // ponytail: that leaves a 28pt target, under the 44pt
                    // guideline. Padding it out moves the circles off Figma's
                    // coordinates, so widen it only if it misses in the field.
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to step \(step)")
        } else {
            stepCircleBody(step)
        }
    }

    private func stepCircleBody(_ step: Int) -> some View {
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

struct AddNestSectionTitle: View {
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
struct AddNestDisclosureRow: View {
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

/// A read-only identifier: label above, assigned value below, no field
/// chrome. Both identifiers on the identity screen are issued by the app --
/// the nest number from the hatchery's sequence, the bucket ID from the NFC
/// tag once that exists -- so neither is ever typed.
struct AddNestLabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appNeutralGray2)

            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .fontWeight(.regular)
                .foregroundStyle(.black)
                // Fixed-width digits: the value is re-issued while the screen
                // is up, and proportional digits reflow the row as it lands.
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A large centered numeric readout that doubles as its own text field: the
/// egg count and the "after X days" count share this exact look in the
/// design, so it is one component used twice rather than two near-identical
/// fields.
struct AddNestBigNumberField: View {
    /// Omitted for the days field, which is already introduced by the row
    /// above it ("Inspection date will be in ...").
    var label: String? = nil
    @Binding var text: String
    /// The screen's own focus flag; see `AddNestBigNumberField`'s use of it.
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

struct AddNestTimelineDateBlock: View {
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
struct AddNestInspectionModeControl: View {
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

/// Inline rather than sheet-based so the related form fields remain visible
/// while the user chooses a date.
struct AddNestInlineDatePicker: View {
    @Binding var selection: Date

    var body: some View {
        DatePicker("", selection: $selection, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Color.appGreenPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 370)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#EBEBEB"), lineWidth: 1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

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
    /// call goes to whatever the current first responder is, unscoped.
    /// Clearing a `FocusState` only ever affects the fields actually bound to
    /// it, so it cannot touch anything else on screen.
    ///
    /// Masked off whenever no field is focused. "Simultaneous" only holds
    /// against SwiftUI's own gestures -- the `.graphical` `DatePicker` is a
    /// UIKit `UICalendarView`, whose day-cell recognizer does not cooperate
    /// with a foreign one laid over it, so a permanently-installed tap here
    /// swallowed every date selection. With no keyboard up there is nothing
    /// to dismiss anyway, so the gesture simply should not exist then.
    func dismissesKeyboardOnTap(_ isFieldFocused: FocusState<Bool>.Binding) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                isFieldFocused.wrappedValue = false
            },
            including: isFieldFocused.wrappedValue ? .all : .subviews
        )
    }
}
