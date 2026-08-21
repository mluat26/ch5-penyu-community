import Foundation

/// Turns a nest's readings into the bars of the hatch report's temperature
/// chart.
///
/// Free of SwiftUI so it can be tested directly: the bucketing is where this
/// goes wrong, not the drawing.
enum NestTemperatureBuckets {
    /// One bar of the chart.
    struct Bar: Equatable {
        /// Days since the start of the span, for the x axis.
        let dayOffset: Int
        /// How many days this bar covers. 1 for a short incubation, more once
        /// the span is long enough that a bar per day stops being legible.
        let dayCount: Int
        /// The mean of the readings across those days, or nil where nothing
        /// was recorded so the chart draws a stub rather than closing the gap.
        let meanC: Double?
    }

    /// The most bars the 341pt plot can hold and still read as bars rather
    /// than a comb. Past this, days are grouped.
    static let maximumBars = 24

    /// Bars across `interval`, oldest first.
    ///
    /// A day's contribution is the mean of its readings, not its peak: a
    /// single spike should not redraw a whole day as an emergency, and the
    /// daily mean is the figure the infobook's acceptable band is written
    /// against. Grouped bars are the mean of the readings in the group, so a
    /// dead-logger day inside a group neither counts as cold nor drags the
    /// group's mean toward whatever the working days happened to read.
    static func bars(
        across interval: DateInterval,
        readings: [IoTDataEntity],
        calendar: Calendar = .current
    ) -> [Bar] {
        let first = calendar.startOfDay(for: interval.start)
        let last = calendar.startOfDay(for: interval.end)
        let span = max(calendar.dateComponents([.day], from: first, to: last).day ?? 0, 0)
        let dayCount = span + 1

        // Ceiling division: as few days per bar as fits inside the cap.
        let daysPerBar = (dayCount + maximumBars - 1) / maximumBars

        var totals: [Int: (sum: Double, count: Int)] = [:]
        for reading in readings {
            let day = calendar.startOfDay(for: reading.timestamp)
            guard let offset = calendar.dateComponents([.day], from: first, to: day).day,
                  offset >= 0, offset < dayCount
            else { continue }

            let bar = offset / daysPerBar
            let running = totals[bar] ?? (0, 0)
            totals[bar] = (running.sum + reading.temperatureC, running.count + 1)
        }

        return stride(from: 0, to: dayCount, by: daysPerBar).enumerated().map { index, offset in
            Bar(
                dayOffset: offset,
                dayCount: min(daysPerBar, dayCount - offset),
                meanC: totals[index].map { $0.sum / Double($0.count) }
            )
        }
    }

    /// The x-axis step, in days, for a span of `dayCount` days: the finest of
    /// these that still leaves at most a handful of labels, so a 3-week
    /// incubation is marked in days and a 3-month one in fortnights rather
    /// than crowding.
    static func axisStep(dayCount: Int) -> Int {
        [1, 2, 5, 10, 15, 30, 60].first { dayCount / $0 <= 6 } ?? 90
    }

    /// The day number this bar's x-axis label should show, or nil when no
    /// multiple of `step` falls inside the days it covers.
    ///
    /// A bar spans several days once the incubation is long, so "label the
    /// bars whose offset is a multiple of the step" would label only day 0 --
    /// bar offsets go up in whole bars, not in steps.
    static func axisMark(for bar: Bar, step: Int) -> Int? {
        guard step > 0 else { return nil }
        // The first multiple of `step` at or after this bar's first day.
        let mark = ((bar.dayOffset + step - 1) / step) * step
        return mark < bar.dayOffset + bar.dayCount ? mark : nil
    }
}
