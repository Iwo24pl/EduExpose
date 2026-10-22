import Foundation

// MARK: - Coding

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

extension JSONDecoder {
    /// VULCAN uses PascalCase keys; Swift properties are lowerCamelCase.
    static func vulcan() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            guard let key = keys.last?.stringValue, let first = key.first else {
                return AnyCodingKey(stringValue: "")
            }
            return AnyCodingKey(stringValue: first.lowercased() + key.dropFirst())
        }
        return decoder
    }
}

enum VulcanError: LocalizedError {
    case noStudent
    case noPeriod
    case invalidResponse
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noStudent: return "Najpierw wybierz ucznia."
        case .noPeriod: return "Konto nie ma aktywnego okresu."
        case .invalidResponse: return "Serwer zwrócił nieoczekiwaną odpowiedź."
        case .message(let text): return text
        }
    }
}

// MARK: - Account

struct Pupil: Codable, Sendable {
    let id: Int
    let firstName: String
    let secondName: String?
    let surname: String
}

struct SchoolUnit: Codable, Sendable {
    let id: Int
    let symbol: String
    let short: String
    let restURL: String
    let name: String
    let displayName: String
}

struct ConstituentUnit: Codable, Sendable {
    let id: Int
    let short: String
    let name: String
}

struct Period: Codable, Identifiable, Sendable {
    let id: Int
    let level: Int?
    let number: Int?
    let startAt: String
    let endAt: String
    let current: Bool?
    let last: Bool?
}

struct Journal: Codable, Sendable {
    let id: Int
    let startAt: String?
    let endAt: String?
    let pupilNumber: Int?
}

struct AccountMessageBox: Codable, Sendable {
    let id: Int
    let globalKey: String
    let name: String
}

struct Account: Codable, Identifiable, Sendable {
    let classDisplay: String?
    let infoDisplay: String?
    let unit: SchoolUnit
    let constituentUnit: ConstituentUnit
    let pupil: Pupil
    let periods: [Period]?
    let journal: Journal?
    let messageBox: AccountMessageBox?

    var id: String {
        "\(pupil.id)-\(unit.id)-\(constituentUnit.id)-\(journal?.id ?? 0)"
    }

    var displayName: String { "\(pupil.firstName) \(pupil.surname)" }

    var schoolName: String {
        unit.displayName.isEmpty ? unit.name : unit.displayName
    }

    var classLabel: String? {
        if let classDisplay, !classDisplay.isEmpty { return classDisplay }
        return nil
    }

    var currentPeriod: Period? {
        if let current = periods?.first(where: { $0.current == true }) { return current }
        return periods?.last
    }
}

// MARK: - Grades

struct Subject: Codable, Identifiable, Sendable {
    let id: Int
    let key: String?
    let name: String
    let kod: String?
    let position: Int?
}

struct Employee: Codable, Identifiable, Sendable {
    let id: Int
    let surname: String
    let name: String
    let displayName: String
}

struct GradeCategory: Codable, Sendable {
    let id: Int
    let name: String
    let code: String?
}

struct GradeColumn: Codable, Sendable {
    let id: Int
    let key: String?
    let periodId: Int?
    let name: String
    let code: String?
    let group: String?
    let number: Int?
    let color: Int?
    let weight: Double?
    let subject: Subject
    let category: GradeCategory?
}

struct Grade: Codable, Identifiable, Sendable {
    let id: Int
    let key: String?
    let pupilId: Int?
    let contentRaw: String?
    let content: String?
    let comment: String?
    let value: Double?
    let createdAt: String?
    let modifiedAt: String?
    let column: GradeColumn
    let correctedGrade: String?

    var display: String {
        if let content, !content.isEmpty { return content }
        if let value { return value.clean }
        return "-"
    }

    var numericValue: Double? { value ?? Double(display.replacingOccurrences(of: ",", with: ".")) }
}

struct GradeAverage: Codable, Identifiable, Sendable {
    let id: Int
    let pupilId: Int?
    let periodId: Int?
    let subject: Subject
    let average: String?
    let points: String?
    let scope: String?
}

// MARK: - Exams, homework, notes, announcements

struct Attachment: Codable, Sendable {
    let name: String
    let link: String?
}

struct Exam: Codable, Identifiable, Sendable {
    let id: Int
    let key: String?
    let type: String
    let typeId: Int?
    let content: String
    let deadline: String
    let createdAt: String?
    let subject: Subject
    let creator: Employee?
}

struct Homework: Codable, Identifiable, Sendable {
    let id: Int
    let key: String?
    let content: String
    let isAnswerRequired: Bool?
    let date: String?
    let deadline: String
    let subject: Subject
    let creator: Employee?
    let attachments: [Attachment]?
}

struct NoteCategory: Codable, Sendable {
    let id: Int
    let name: String
    let type: String?
}

struct Note: Codable, Identifiable, Sendable {
    let id: Int
    let positive: Bool
    let dateValid: String
    let dateModify: String?
    let category: NoteCategory?
    let content: String
    let points: Int?
    let creator: Employee?
}

struct Announcement: Codable, Identifiable, Sendable {
    let id: Int
    let unitId: Int?
    let title: String
    let content: String
    let category: String?
    let dateFrom: String?
    let dateTo: String?
    let sender: Employee?
    let createdAt: String?
    let attachments: [Attachment]?
}

// MARK: - Schedule

struct ScheduleChange: Codable, Sendable {
    let id: Int
    let type: Int
    let isMerge: Bool?
    let separation: Bool?
}

struct Room: Codable, Sendable {
    let id: Int
    let code: String
}

struct Timeslot: Codable, Identifiable, Sendable {
    let id: Int
    let start: String
    let end: String
    let display: String?
    let position: Int
}

struct ScheduleSubstitution: Codable, Sendable {
    let id: Int
    let date: String?
    let pupilNote: String?
    let reason: String?
    let event: String?
    let room: Room?
    let timeSlot: Timeslot?
    let subject: Subject?
    let teacherPrimary: Employee?
    let teacherAbsenceReasonId: Int?
    let teacherAbsenceEffectName: String?
    let change: ScheduleChange?
    let classAbsence: Bool?
    let noRoom: Bool?
    let description: String?
}

struct Schedule: Codable, Identifiable, Sendable {
    let id: Int
    let mergeChangeId: Int?
    let event: String?
    let date: String
    let room: Room?
    let timeSlot: Timeslot
    let subject: Subject?
    let teacherPrimary: Employee?
    let substitution: ScheduleSubstitution?

    var isCanceled: Bool {
        guard let sub = substitution else { return false }
        return sub.classAbsence == true
            || (sub.teacherAbsenceReasonId != nil && sub.teacherPrimary == nil)
            || sub.change?.type == 2
            || (sub.teacherAbsenceEffectName?.localizedCaseInsensitiveContains("odwołan") ?? false)
    }

    var isRescheduled: Bool {
        guard let sub = substitution else { return false }
        if let subDate = sub.date, subDate != date { return true }
        if let slot = sub.timeSlot, slot.position != timeSlot.position { return true }
        return false
    }

    var effectiveDate: String { substitution?.date ?? date }
    var effectiveSlot: Timeslot { substitution?.timeSlot ?? timeSlot }
    var effectiveSubject: Subject? { substitution?.subject ?? subject }
    var effectiveTeacher: Employee? { substitution?.teacherPrimary ?? teacherPrimary }
    var effectiveRoom: Room? { substitution?.room ?? room }

    var noteOrReason: String? {
        if let note = substitution?.pupilNote, !note.isEmpty { return note }
        if let reason = substitution?.reason, !reason.isEmpty { return reason }
        if let description = substitution?.description, !description.isEmpty { return description }
        if let effect = substitution?.teacherAbsenceEffectName, !effect.isEmpty { return effect }
        if let event, !event.isEmpty { return event }
        return nil
    }
}

// MARK: - Messages

struct MessageAddress: Codable, Sendable {
    let globalKey: String
    let name: String
}

struct Message: Codable, Identifiable, Sendable {
    let id: String
    let globalKey: String
    let threadKey: String?
    let subject: String
    let content: String
    let sentAt: String
    let readAt: String?
    let status: Int
    let sender: MessageAddress
    let receiver: [MessageAddress]?
    let attachments: [Attachment]?
    let withdrawn: Bool?
}

enum MessageKind: String, CaseIterable, Identifiable, Sendable {
    case received = "Odebrane"
    case sent = "Wysłane"
    case deleted = "Kosz"

    var id: String { rawValue }
}

// MARK: - Misc

struct LuckyNumber: Codable, Sendable {
    let day: String
    let number: Int
}

struct ApiStatus: Codable, Sendable {
    let code: Int
    let message: String
}

struct EnvelopeBox<T: Decodable>: Decodable {
    let status: ApiStatus
    let envelope: T?
}

// MARK: - Stored session

struct HebeCredential: Codable, Sendable {
    var type: String
    var restUrl: String?
    var certificate: String
    var privateKey: String
    var fingerprint: String
    var deviceId: String
    var deviceOs: String
    var deviceModel: String
    var notificationToken: String?
}

struct StoredStudent: Codable, Identifiable, Sendable {
    var id: String
    var account: Account
    var credential: HebeCredential
    var restUrl: String
    var login: String?
    var password: String?
    var tenant: String?
    var isEnabled: Bool
}

// MARK: - Dates

enum VulcanDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pl_PL")
        calendar.firstWeekday = 2
        return calendar
    }

    /// Parses yyyy-MM-dd as local noon, so time zones never shift the day.
    static func day(_ raw: String) -> Date? {
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }

    static func dateTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let normalized = String(trimmed.prefix(19)).replacingOccurrences(of: " ", with: "T")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: normalized)
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func startOfWeek(_ date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.startOfDay(for: addDays(date, -daysFromMonday))
    }

    static func label(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: date)
    }

    static func shortLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func weekdayShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EE"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func time(_ raw: String) -> String {
        let parts = raw.split(separator: ":")
        guard parts.count >= 2 else { return raw }
        return "\(parts[0]):\(parts[1])"
    }

    static func dateTimeLabel(_ raw: String) -> String {
        guard let date = dateTime(raw) else { return String(raw.prefix(16)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    static func dayLabel(_ raw: String) -> String {
        guard let date = day(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }
}

extension Double {
    var clean: String {
        if rounded() == self { return String(Int(self)) }
        return String(format: "%.2f", self).replacingOccurrences(of: ".", with: ",")
    }
}
