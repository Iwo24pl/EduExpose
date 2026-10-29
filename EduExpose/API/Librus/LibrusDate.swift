import Foundation

/// Librus runs on Polish school time. "Today", the lucky number and a week
/// start must not depend on the device's time zone.
enum LibrusDate {
    static let timeZone = TimeZone(identifier: "Europe/Warsaw")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pl_PL")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func todayString() -> String {
        dayString(Date())
    }

    static func date(fromDay raw: String) -> Date? {
        let text = String(raw.prefix(10))
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        components.timeZone = timeZone
        return calendar.date(from: components)
    }

    static func weekStart(_ date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
        return calendar.startOfDay(for: start)
    }

    static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func isDay(_ day: String, between from: String, to: String) -> Bool {
        let value = String(day.prefix(10))
        return value >= from && value <= to
    }

    /// Two semester boundaries for schools where the class endpoint is
    /// unavailable. Polish schools conventionally split at the end of
    /// January and finish at the end of June.
    static func schoolYearStrings(around date: Date) -> (start: String, mid: String, end: String) {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2026
        let month = components.month ?? 9
        let startYear = month >= 9 ? year : year - 1
        return (
            makeDate(year: startYear, month: 9, day: 1),
            makeDate(year: startYear + 1, month: 1, day: 31),
            makeDate(year: startYear + 1, month: 6, day: 30)
        )
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = timeZone
        guard let date = calendar.date(from: components) else {
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        return dayString(date)
    }
}
