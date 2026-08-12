import Foundation

enum AppDateFormatting {
    static func parseNestDraftDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.date(from: text)
    }
}
