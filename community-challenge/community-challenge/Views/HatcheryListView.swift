import SwiftUI

/// The hatcheries the current user can reach, shown at launch and from the
/// home header.
///
/// Access is scoped by the database, not here: `hatcheryService.hatcheries()`
/// returns whatever the caller is allowed to read. Today the dev anon policy
/// means that is every row; once authentication and ownership policies land,
/// the same call returns only the signed-in user's hatcheries and this view is
/// unchanged.
private struct HatcheryListContent: View {
    let controller: HatcheryListController
    let activeHatcheryID: UUID?
    let createTitle: String
    let onSelect: (HatcherySessionState) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.appRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            if !controller.hatcheries.isEmpty {
                hatcheryList
            }

            Button(action: onCreateNew) {
                Text(createTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appGreenPrimary)
            }
            .buttonStyle(.plain)
            .frame(height: 44)
        }
    }

    private var hatcheryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(controller.hatcheries.enumerated()), id: \.element.id) { index, hatchery in
                Button {
                    guard let session = controller.session(for: hatchery) else { return }
                    onSelect(session)
                } label: {
                    row(hatchery)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(height: 72)
                .overlay(alignment: .bottom) {
                    if index < controller.hatcheries.count - 1 {
                        Rectangle()
                            .fill(Color(hex: "#EEEEEE"))
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(width: 371)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func row(_ hatchery: HatcheryEntity) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hatchery.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2B2B2B"))
                    .lineLimit(1)

                Text("\(hatchery.numberOfRows) × \(hatchery.numberOfColumns) sections")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#8E8E93"))
            }

            Spacer(minLength: 0)

            if hatchery.id == activeHatcheryID {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appGreenPrimary)
                    .accessibilityLabel("Currently open")
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sheet presentation, opened from the hatchery name in the home header.
struct HatcheryListView: View {
    let controller: HatcheryListController
    let activeHatcheryID: UUID
    let onSelect: (HatcherySessionState) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        SheetChrome(title: "Hatcheries") { sheetWidth in
            HatcheryListContent(
                controller: controller,
                activeHatcheryID: activeHatcheryID,
                createTitle: "New hatchery",
                onSelect: onSelect,
                onCreateNew: onCreateNew
            )
            .frame(width: 371, alignment: .top)
            .offset(x: ceil((sheetWidth - 371) / 2), y: 71)
        }
        .task { await controller.load() }
    }
}

/// Launch presentation, shown instead of the setup flow when the user already
/// has hatcheries to open. Without it, `AppSessionController.activeHatchery`
/// being in-memory means every relaunch forces creating another hatchery to get
/// back to the ones already saved.
struct HatcheryPickerView: View {
    let controller: HatcheryListController
    let onSelect: (HatcherySessionState) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Your hatcheries")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            HatcheryListContent(
                controller: controller,
                activeHatcheryID: nil,
                createTitle: "New hatchery",
                onSelect: onSelect,
                onCreateNew: onCreateNew
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 72)
        .background(Color.appOffWhite.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
