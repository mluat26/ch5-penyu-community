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
