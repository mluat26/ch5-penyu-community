import Foundation

enum AppDateFormatting {
    static func parseNestDraftDate(_ text: String) -> Date? {
        nestDraftDateFormatter.date(from: text)
    }

    static func nestDraftDateString(_ date: Date) -> String {
        nestDraftDateFormatter.string(from: date)
    }

    static func longNestDraftDate(_ text: String) -> String {
        guard let date = parseNestDraftDate(text) else { return text }
        return longDateFormatter.string(from: date)
    }

    /// "20th June, 2026" -- the reading style the hatchling screens use for a
    /// real `Date`, as `longNestDraftDate` does for the draft's `String` form.
    ///
    /// Lives here because two screens need it and one of them was getting it
    /// wrong: HatchForm1 built a `DateFormatter` with the literal suffix `'th'`
    /// baked into its format string, so it rendered "1th", "2th", "3th".
    static func ordinalDate(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch (day % 10, day % 100) {
        case (1, let hundred) where hundred != 11: suffix = "st"
        case (2, let hundred) where hundred != 12: suffix = "nd"
        case (3, let hundred) where hundred != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix) \(date.formatted(.dateTime.month(.wide).year()))"
    }

    private static var nestDraftDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }

    private static var longDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }
}
