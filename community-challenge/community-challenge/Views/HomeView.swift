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

    let onAddNest: () -> Void

    private let columns = ["A", "B", "C", "D"]
    private let rows = ["1", "2", "3"]

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

                VStack(spacing: 0) {
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
            }
        }
    }

    private func header(screenWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Hatch_01")
                    .font(.body)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(Color(hex: "#0C7C4D"))
            .frame(width: 101, height: 44, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                toolbarIcon(systemName: "bell", label: "Notifications")
                toolbarIcon(systemName: "person", label: "Profile")
            }
            .frame(width: 148, height: 48)
        }
        .frame(width: max(screenWidth - 16, 0), height: 48)
        .padding(.leading, 16)
    }

    private func toolbarIcon(systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(.black)
            .frame(width: 44, height: 44)
            .background(.white, in: Circle())
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.06), lineWidth: 1)
            }
            .frame(width: 72, height: 48)
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

                        if row != rows.last {
                            Spacer()
                        }
                    }
                }
                .frame(width: 9, height: max(height - 80, 0), alignment: .top)
                .padding(.top, 40)
                .frame(width: 9, height: height, alignment: .top)

                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(hex: "#BFCABD"))

                    if selectedSectionID == nil {
                        Image(systemName: "photo")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(Color(hex: "#75816F"))
                            .accessibilityLabel("Hatchery image placeholder")
                    }

                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { column in
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
                temperatureCard(value: selectedSection?.averageTemperature ?? "29.0")

                HStack(spacing: 12) {
                    statCard(title: "Nests", value: selectedSection?.nests ?? "312")
                    statCard(title: "Eggs", value: selectedSection?.eggs ?? "4812")
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
    let averageTemperature: String
    let nests: String
    let eggs: String
    let nestReadings: [NestSample]

    static func sample(for id: String) -> HatcherySectionSample {
        HatcherySectionSample(
            id: id,
            averageTemperature: id == "B2" ? "30.0" : "29.0",
            nests: id == "B2" ? "5" : "12",
            eggs: id == "B2" ? "233" : "1,204",
            nestReadings: [
                NestSample(id: "\(id)-one", temperature: "29.0°C", systemName: "checkmark.circle", tint: Color(hex: "#34C759")),
                NestSample(id: "\(id)-two", temperature: "33.5°C", systemName: "heat.waves", tint: Color(hex: "#FF383C")),
                NestSample(id: "\(id)-three", temperature: "26.5°C", systemName: "snowflake", tint: Color(hex: "#00C3D0")),
                NestSample(id: "\(id)-four", temperature: "33.5°C", systemName: "heat.waves", tint: Color(hex: "#FF383C"))
            ]
        )
    }
}

private struct NestSample {
    let id: String
    let temperature: String
    let systemName: String
    let tint: Color
}

private struct SectionOverviewSheet: View {
    let section: HatcherySectionSample

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 54, alignment: .top)
                .padding(.top, 19)

            summary
                .frame(width: 370, height: 85, alignment: .top)
                .padding(.top, 2)

            nestList
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 0) {
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
            .frame(width: 48, height: 44)
            .offset(x: -2)
            .accessibilityLabel("Close section overview")

            Spacer(minLength: 0)

            Text("Section \(section.id)")
                .font(.system(size: 17, weight: .semibold))

            Spacer(minLength: 0)

            Image(systemName: "pencil")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.blue, in: Circle())
            .frame(width: 48, height: 44)
            .accessibilityLabel("Edit section \(section.id)")
        }
        .padding(.horizontal, 16)
        .frame(height: 44, alignment: .top)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            summaryValue(
                title: "Average temperature",
                value: section.averageTemperature,
                unit: "°C",
                valueColor: Color(hex: "#0C7C4D"),
                alignment: .leading
            )
            .frame(width: 151, height: 85, alignment: .topLeading)

            summaryValue(title: "Nests", value: section.nests)
                .frame(width: 97.5, height: 85, alignment: .top)

            summaryValue(title: "Eggs", value: section.eggs)
                .frame(width: 97.5, height: 85, alignment: .top)
        }
        .frame(width: 370, height: 85, alignment: .top)
    }

    private func summaryValue(
        title: String,
        value: String,
        unit: String = "",
        valueColor: Color = Color(hex: "#2B2B2B"),
        alignment: HorizontalAlignment = .center
    ) -> some View {
        let isTemperature = !unit.isEmpty

        return VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(hex: "#8E8E93").opacity(0.75))
                .lineLimit(1)
                .padding(.leading, alignment == .leading ? 8 : 0)

            HStack(alignment: .top, spacing: 0) {
                Text(value)
                    .font(.system(size: isTemperature ? 28 : 17, weight: isTemperature ? .bold : .semibold))
                    .tracking(isTemperature ? 0.38 : 0)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.top, 1)
                }
            }
            .foregroundStyle(valueColor)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .topLeading : .top)
    }

    private var nestList: some View {
        VStack(spacing: 0) {
            ForEach(Array(section.nestReadings.enumerated()), id: \.element.id) { index, nest in
                nestRow(nest)
                    .padding(.horizontal, 16)
                    .frame(height: index == 0 ? 122 : index == 3 ? 120 : 121)
                    .overlay(alignment: .bottom) {
                        if index < section.nestReadings.count - 1 {
                            Rectangle()
                                .fill(Color(hex: "#EEEEEE"))
                                .frame(height: 1)
                        }
                    }
            }
        }
        .frame(width: 387, height: 484)
        .background(.white, in: RoundedRectangle(cornerRadius: 27))
        .clipShape(RoundedRectangle(cornerRadius: 27))
    }

    private func nestRow(_ nest: NestSample) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Nest #023")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2B2B2B"))

                Text("· 100 eggs")
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

            Spacer(minLength: 0)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: nest.systemName)
                        .font(.system(size: 12, weight: .regular))

                    Text(nest.temperature)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14.5)
                .frame(height: 38)
                .background(nest.tint, in: RoundedRectangle(cornerRadius: 17))

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: "#0C7C4D"))
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 17)
        .padding(.bottom, 17)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hatchery Overview", traits: .fixedLayout(width: 402, height: 874)) {
    HomeView(onAddNest: { })
}
