import XCTest
@testable import community_challenge

/// The hatch report's chart is a bar per day of the incubation, grouped once
/// there are more days than bars will fit. What can go wrong is the bucketing
/// and the axis marks, not the drawing, so that is what this covers.
final class NestTemperatureBucketsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 4, day: day, hour: hour
        ))!
    }

    private func reading(_ date: Date, _ temperatureC: Double) -> IoTDataEntity {
        IoTDataEntity(
            id: UUID(),
            nestID: UUID(),
            temperatureC: temperatureC,
            timestamp: date
        )
    }

    private func bars(from: Int, to: Int, readings: [IoTDataEntity] = []) -> [NestTemperatureBuckets.Bar] {
        NestTemperatureBuckets.bars(
            across: DateInterval(start: day(from), end: day(to)),
            readings: readings,
            calendar: calendar
        )
    }

    /// Both endpoints are drawn. A 1st-to-5th incubation is five bars, not
    /// four: the day the eggs were laid is part of the record.
    func testShortSpanIsOneBarPerDayIncludingBothEnds() {
        let bars = bars(from: 1, to: 5)

        XCTAssertEqual(bars.count, 5)
        XCTAssertEqual(bars.map(\.dayOffset), [0, 1, 2, 3, 4])
        XCTAssertEqual(bars.map(\.dayCount), [1, 1, 1, 1, 1])
    }

    func testSingleDayIsOneBar() {
        let bars = NestTemperatureBuckets.bars(
            across: DateInterval(start: day(1, hour: 2), end: day(1, hour: 23)),
            readings: [],
            calendar: calendar
        )

        XCTAssertEqual(bars.count, 1)
    }

    /// The whole point of the change: 90 days must not draw 90 hairline bars.
    func testLongSpanGroupsDaysToStayUnderTheCap() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let bars = NestTemperatureBuckets.bars(
            across: DateInterval(start: start, end: day(1)),  // 1 Jan – 1 Apr, 91 days
            readings: [],
            calendar: calendar
        )

        XCTAssertLessThanOrEqual(bars.count, NestTemperatureBuckets.maximumBars)
        XCTAssertEqual(bars.first?.dayCount, 4)
        // Every day of the span is covered exactly once, with no overlap.
        XCTAssertEqual(bars.map(\.dayCount).reduce(0, +), 91)
        XCTAssertEqual(bars.last?.dayOffset, 88)
        XCTAssertEqual(bars.last?.dayCount, 3, "The final group is short, not padded past the end")
    }

    /// A bar is the mean of its readings, not the first or the peak -- which
    /// is the whole reason this is a daily chart rather than an hourly one
    /// sampled once.
    func testEachBarIsTheMeanOfItsReadings() {
        let bars = bars(
            from: 1,
            to: 3,
            readings: [
                reading(day(1, hour: 3), 28),
                reading(day(1, hour: 15), 32),   // mean 30
                reading(day(3, hour: 9), 27),
                // Day 2 has nothing.
            ]
        )

        XCTAssertEqual(bars.count, 3)
        XCTAssertEqual(bars[0].meanC!, 30, accuracy: 0.001)
        XCTAssertNil(bars[1].meanC, "A day with no readings must stay a stub")
        XCTAssertEqual(bars[2].meanC!, 27, accuracy: 0.001)
    }

    /// Readings outside the drawn span are ignored rather than folded into
    /// the nearest bar.
    func testReadingsOutsideTheSpanAreDropped() {
        let bars = bars(from: 2, to: 2, readings: [reading(day(1), 99), reading(day(2), 30)])

        XCTAssertEqual(bars.map(\.meanC), [30])
    }

    // MARK: - Axis

    func testAxisStepCoarsensWithTheSpan() {
        XCTAssertEqual(NestTemperatureBuckets.axisStep(dayCount: 6), 1)
        XCTAssertEqual(NestTemperatureBuckets.axisStep(dayCount: 56), 10)
        XCTAssertEqual(NestTemperatureBuckets.axisStep(dayCount: 91), 15)
    }

    /// The bug this formula exists to avoid: with 4 days per bar, no bar
    /// offset is a multiple of 15, so testing the offset alone would label
    /// day 0 and nothing else.
    func testAxisMarksLandOnGroupedBars() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let bars = NestTemperatureBuckets.bars(
            across: DateInterval(start: start, end: day(1)),
            readings: [],
            calendar: calendar
        )

        let marks = bars.compactMap { NestTemperatureBuckets.axisMark(for: $0, step: 15) }

        XCTAssertEqual(marks, [0, 15, 30, 45, 60, 75, 90])
    }

    func testAxisMarkIsNilBetweenSteps() {
        let bar = NestTemperatureBuckets.Bar(dayOffset: 4, dayCount: 4, meanC: nil)

        XCTAssertNil(NestTemperatureBuckets.axisMark(for: bar, step: 15))
    }
}
