//
//  HomeScreen.swift
//  community-challenge
//
//  Created by Nguyen Minh Luat on 10/8/26.
//

import SwiftUI

struct HomeView: View {
    @State private var selectedSectionID: String?
    @State private var showsSectionSheet = false

    let hatchery: SavedHatchery
    let onAddNest: () -> Void

    private var columns: [String] { hatchery.grid.columnLabels }
    private var rows: [String] { hatchery.grid.rowLabels }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = min(geometry.size.width, 402)
            let contentWidth = min(max(screenWidth - 32, 0), 370)
            let gridWidth = max(contentWidth - 21, 0)
            let gridHeight = gridWidth * 279 / 349

            ZStack(alignment: .topLeading) {
                Color.white
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(Color(hex: "#FEF6ED"))
                            .frame(width: 621, height: 621)
                            .offset(x: -110, y: -378)
                            .allowsHitTesting(false)
                    }

                VStack(alignment: .leading, spacing: 0) {
                    header(screenWidth: screenWidth)
                        .padding(.top, 87)

                    hatcheryGrid(width: gridWidth, height: gridHeight)
                        .padding(.top, 25)

                    overview(width: contentWidth)
                        .padding(.top, 25)

                    Button {
                        onAddNest()
                    } label: {
                        Text("Add new nest")
                            .font(.body)
                            .fontWeight(.semibold)
                            .tracking(-0.43)
                            .foregroundStyle(Color(hex: "#FAF8F4"))
                            .frame(maxWidth: .infinity, minHeight: 55)
                    }
                    .buttonStyle(.plain)
                    .background(Color(hex: "#2E7D5B"), in: RoundedRectangle(cornerRadius: 26))
                    .frame(width: contentWidth, height: 55)
                    .padding(.top, 36)
                    .padding(.leading, 16)
                }
                .frame(width: screenWidth, alignment: .leading)
            }
            .frame(width: screenWidth, height: geometry.size.height, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .sheet(isPresented: $showsSectionSheet) {
            if let selectedSection {
                SectionOverviewSheet(section: selectedSection)
                    .presentationDetents([.height(707)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(34)
                    .presentationSizing(.page)
            }
        }
    }

    private func header(screenWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(hatchery.hatchery.name)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(Color(hex: "#0C7C4D"))
            .frame(width: 101, height: 44, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                toolbarIcon(systemName: "bell"
                            , label: "Notifications")
                toolbarIcon(systemName: "person", label: "Profile")
            }
            .frame(width: 148, height: 48)
        }
        .frame(width: max(screenWidth - 16, 0), height: 48)
        .padding(.leading, 16)
    
    }

    private func toolbarIcon(
        systemName: String,
        label: String
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(.black)
            .frame(width: 48, height: 48)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(label)
    }

    private func hatcheryGrid(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 21)

                HStack(spacing: 2) {
                    ForEach(columns, id: \.self) { column in
                        Text(column)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: width)
            }
            .frame(width: width + 21, height: 16, alignment: .leading)

            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        Text(row)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.5))
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 9, height: height, alignment: .top)

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(hex: "#BFCABD"))

                    Image(uiImage: hatchery.rectifiedPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                        .accessibilityLabel("Photo of \(hatchery.hatchery.name)")

                    VStack(spacing: 2) {
                        ForEach(rows.indices, id: \.self) { row in
                            HStack(spacing: 2) {
                                ForEach(columns.indices, id: \.self) { column in
                                    let sectionID = "\(columns[column])\(rows[row])"

                                    Button {
                                        selectedSectionID = sectionID
                                    } label: {
                                        Color(hex: "#003C22")
                                            .opacity(selectedSectionID == sectionID ? 0.70 : 0.30)
                                            .overlay {
                                                if selectedSectionID == sectionID {
                                                    sectionBadge(sectionID)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("Section \(sectionID)")
                                }
                            }
                        }
                    }
                    .padding(8)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .frame(width: width + 21, height: height, alignment: .leading)
        }
        .frame(width: width + 21, alignment: .leading)
        .padding(.leading, 16)
    }

    private func overview(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    overviewKicker
                        .font(.footnote)
                        .tracking(-0.08)
                        .lineLimit(1)

                    Text("Check the status of the hatchery")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .tracking(-0.43)
                        .foregroundStyle(Color(hex: "#575757"))
                }

                Spacer(minLength: 0)

                Button {
                    showsSectionSheet = selectedSection != nil
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(Color(hex: "#0C7C4D"))
                        .accessibilityHidden(true)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .disabled(selectedSection == nil)
                .accessibilityLabel("Show section overview")
            }
            .frame(height: 44)

            VStack(spacing: 12) {
                temperatureCard(value: (selectedSection?.averageTemperature ?? 29).celsiusText)

                HStack(spacing: 12) {
                    statCard(title: "Nests", value: (selectedSection?.nests ?? 312).formatted())
                    statCard(title: "Eggs", value: (selectedSection?.eggs ?? 4812).formatted())
                }
                .frame(height: 85)
            }
            .padding(.top, 24)
        }
        .frame(width: width, height: 269, alignment: .top)
        .padding(.horizontal, 16)
    }

    private func temperatureCard(value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Average temperature")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .opacity(0.8)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Color(hex: "#0C7C4D"))
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .tracking(0.38)

                Text("°C")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.top, 2)
            }
            .foregroundStyle(Color(hex: "#0C7C4D"))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
        .background(cardBackground)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .opacity(0.8)

            Spacer(minLength: 0)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .tracking(-0.45)
                .foregroundStyle(.black)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.white)
            .shadow(color: .black.opacity(0.05), radius: 10)
    }

    private var selectedSection: HatcherySectionSample? {
        guard let selectedSectionID else { return nil }
        return HatcherySectionSample.sample(for: selectedSectionID)
    }

    private var overviewKicker: Text {
        guard let selectedSection else {
            return Text("HATCHERY OVERVIEW")
                .foregroundColor(Color(hex: "#757575"))
        }

        let sectionName = Text("SECTION \(selectedSection.id)")
            .fontWeight(.bold)
            .foregroundColor(Color(hex: "#0C7C4D"))

        return Text("HATCHERY \(sectionName) OVERVIEW")
            .foregroundColor(Color(hex: "#757575"))
    }

    private func sectionBadge(_ sectionID: String) -> some View {
        Text(sectionID)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.black)
            .frame(width: 35, height: 36)
            .background(.white, in: Capsule())
            .padding(4)
            .background(.white.opacity(0.24), in: Capsule())
            .accessibilityHidden(true)
    }
}

private struct HatcherySectionSample {
    let id: String
    let averageTemperature: Double
    let nests: Int
    let eggs: Int
    let nestReadings: [NestSample]

    static func sample(for id: String) -> HatcherySectionSample {
        HatcherySectionSample(
            id: id,
            averageTemperature: id == "B2" ? 30 : 29,
            nests: id == "B2" ? 5 : 12,
            eggs: id == "B2" ? 233 : 1204,
            nestReadings: [
                NestSample(id: "\(id)-one", name: "Nest-01", eggs: 490, sectionID: id, temperature: 29, systemName: "checkmark.circle", tint: Color(hex: "#34C759"), chipWidth: 85),
                NestSample(id: "\(id)-two", name: "Nest-02", eggs: 100, sectionID: id, temperature: 33.5, systemName: "heat.waves", tint: Color(hex: "#FF383C"), chipWidth: 85),
                NestSample(id: "\(id)-three", name: "Nest-03", eggs: 212, sectionID: id, temperature: 26.5, systemName: "snowflake", tint: Color(hex: "#00C3D0"), chipWidth: 83),
                NestSample(id: "\(id)-four", name: "Nest-04", eggs: 100, sectionID: id, temperature: 33.5, systemName: "heat.waves", tint: Color(hex: "#FF383C"), chipWidth: 85)
            ]
        )
    }
}

struct NestSample: Identifiable {
    let id: String
    let name: String
    let eggs: Int
    let sectionID: String
    let temperature: Double
    let systemName: String
    let tint: Color
    let chipWidth: CGFloat

    static let preview = HatcherySectionSample.sample(for: "B1").nestReadings[0]
}

extension Double {
    /// Temperatures always render with one decimal: 29 → "29.0".
    var celsiusText: String { formatted(.number.precision(.fractionLength(1))) }
}

/// Header chrome plus the Figma-literal sizing shared by the section and nest sheets.
struct SheetChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: (CGFloat) -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            // iOS 26 fits a 402-point page sheet inside its system side margins.
            // Cancel that fit only for the Figma reference width so point sizes stay literal.
            let isReferenceWidth = abs(geometry.size.width - 402) < 0.5
            let pageInset = isReferenceWidth ? geometry.frame(in: .global).minX : 0
            let sheetWidth = geometry.size.width - (pageInset * 2)
            let contentScale = geometry.size.width / sheetWidth

            ZStack(alignment: .topLeading) {
                header(width: sheetWidth)
                    .frame(height: 54)
                    .offset(y: 11)

                content(sheetWidth)
            }
            .frame(width: sheetWidth, height: geometry.size.height, alignment: .topLeading)
            .scaleEffect(contentScale, anchor: .topLeading)
        }
    }

    private func header(width: CGFloat) -> some View {
        let horizontalInset = max((width - 358) / 2, 0)

        return ZStack {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.black)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(.white)
            .frame(width: 44, height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, horizontalInset)
            .accessibilityLabel("Close \(title)")

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .offset(y: 2)

            Image(systemName: "pencil")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.blue, in: Circle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, horizontalInset)
                .accessibilityLabel("Edit \(title)")
        }
        .frame(width: width, height: 44, alignment: .top)
    }
}

/// One column of a sheet summary row: caption on top, value (optionally with a unit) below.
func sheetSummaryValue(
    title: String,
    value: String,
    unit: String = "",
    valueColor: Color = .black,
    alignment: HorizontalAlignment = .center
) -> some View {
    let isTemperature = !unit.isEmpty

    return VStack(alignment: alignment, spacing: 4) {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(hex: "#8E8E93").opacity(0.75))
            .lineLimit(1)
            .padding(.leading, alignment == .leading ? 16 : 0)

        HStack(alignment: .top, spacing: 0) {
            Text(value)
                .font(.system(size: isTemperature ? 28 : 20, weight: isTemperature ? .bold : .semibold))
                .tracking(isTemperature ? 0.38 : 0)

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.top, 1)
            }
        }
        .foregroundStyle(valueColor)
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: isTemperature ? 0 : 10)
    }
    .padding(.top, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .topLeading : .top)
}

private struct SectionOverviewSheet: View {
    let section: HatcherySectionSample

    @State private var selectedNest: NestSample?

    var body: some View {
        SheetChrome(title: "Section \(section.id)") { sheetWidth in
            summary
                .frame(width: 370, height: 85, alignment: .top)
                .offset(x: (sheetWidth - 370) / 2, y: 71)

            nestList
                .offset(x: ceil((sheetWidth - 371) / 2), y: 167)
        }
        .sheet(item: $selectedNest) { nest in
            NestDetailView(nest: nest)
                .presentationDetents([.height(707)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationSizing(.page)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            sheetSummaryValue(
                title: "Average temperature",
                value: section.averageTemperature.celsiusText,
                unit: "°C",
                valueColor: Color(hex: "#0C7C4D"),
                alignment: .leading
            )
            .frame(width: 151, height: 85, alignment: .topLeading)

            sheetSummaryValue(title: "Nests", value: section.nests.formatted())
                .frame(width: 97.5, height: 85, alignment: .top)

            sheetSummaryValue(title: "Eggs", value: section.eggs.formatted())
                .frame(width: 97.5, height: 85, alignment: .top)
        }
        .frame(width: 370, height: 85, alignment: .top)
    }

    private var nestList: some View {
        VStack(spacing: 0) {
            ForEach(Array(section.nestReadings.enumerated()), id: \.element.id) { index, nest in
                Button {
                    selectedNest = nest
                } label: {
                    nestRow(nest)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(height: 116)
                .overlay(alignment: .bottom) {
                    if index < section.nestReadings.count - 1 {
                        Rectangle()
                            .fill(Color(hex: "#EEEEEE"))
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(width: 371, height: 464)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func nestRow(_ nest: NestSample) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 4) {
                Text(nest.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2B2B2B"))

                Text("· \(nest.eggs.formatted()) eggs")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: "#4A4A4A"))

                Spacer(minLength: 0)

                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#4A4A4A").opacity(0.5))

                Text("Hatch in 3 days")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#4A4A4A").opacity(0.5))
            }
            .frame(width: 339, height: 22)
            .offset(x: 16, y: 16)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: nest.systemName)
                        .font(.system(size: 12, weight: .regular))

                    Text("\(nest.temperature.celsiusText)°C")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(width: nest.chipWidth, height: 36)
                .background(nest.tint, in: RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: "#0C7C4D"))
                    .accessibilityHidden(true)
            }
            .frame(width: 339, height: 36)
            .offset(x: 16, y: 64)
        }
        .frame(width: 371, height: 116, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hatchery Overview", traits: .fixedLayout(width: 402, height: 874)) {
    HomeView(hatchery: .previewSample, onAddNest: { })
}

extension SavedHatchery {
    static let previewSample: SavedHatchery = {
        let boundary = HatcheryBoundary.fullImage
        let dimension = HatcheryDimension(widthM: 8, heightM: 6)
        let grid = HatcheryGridGenerator.generate(
            dimension: dimension,
            boundary: boundary
        )!
        return SavedHatchery(
            hatchery: Hatchery(
                id: UUID(),
                name: "Hatch_01",
                shape: .rectangle,
                numberOfRow: grid.rows,
                numberOfColumn: grid.columns,
                lengthM: dimension.heightM,
                widthM: dimension.widthM,
                organizationId: nil
            ),
            rectifiedPhoto: UIImage(named: "HatcherySamplePhoto") ?? UIImage(),
            grid: grid
        )
    }()
}
