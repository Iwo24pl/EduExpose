import Foundation

/// Provider-neutral journal reads used by the screens.
///
/// `AppModel` will hold one of these per student and keep its existing
/// `load…` methods; the screens do not change.
protocol JournalService: Sendable {
    func grades(period: Period?) async throws -> [Grade]
    func averages(period: Period?) async throws -> [GradeAverage]
    func timetable(from: Date, to: Date) async throws -> [Schedule]
    func exams(from: Date, to: Date) async throws -> [Exam]
    func homework(from: Date, to: Date) async throws -> [Homework]
    func notes() async throws -> [Note]
    func announcements() async throws -> [Announcement]
    func luckyNumber(day: Date) async throws -> Int?
}

/// The existing Hebe implementation, moved behind the protocol without
/// changing its behaviour.
struct HebeJournalService: JournalService {
    let client: HebeClient
    let account: Account

    func grades(period: Period?) async throws -> [Grade] {
        guard let period = period ?? account.currentPeriod else {
            throw VulcanError.noPeriod
        }
        return try await client.grades(
            unitId: account.unit.id,
            pupilId: account.pupil.id,
            periodId: period.id
        )
    }

    func averages(period: Period?) async throws -> [GradeAverage] {
        guard let period = period ?? account.currentPeriod else {
            throw VulcanError.noPeriod
        }
        return try await client.averages(
            unitId: account.unit.id,
            pupilId: account.pupil.id,
            periodId: period.id
        )
    }

    func timetable(from: Date, to: Date) async throws -> [Schedule] {
        try await client.schedule(
            pupilId: account.pupil.id,
            from: VulcanDate.dateString(from),
            to: VulcanDate.dateString(to)
        )
    }

    func exams(from: Date, to: Date) async throws -> [Exam] {
        try await client.exams(
            pupilId: account.pupil.id,
            from: VulcanDate.dateString(from),
            to: VulcanDate.dateString(to)
        )
    }

    func homework(from: Date, to: Date) async throws -> [Homework] {
        try await client.homework(
            pupilId: account.pupil.id,
            from: VulcanDate.dateString(from),
            to: VulcanDate.dateString(to)
        )
    }

    func notes() async throws -> [Note] {
        try await client.notes(pupilId: account.pupil.id)
    }

    func announcements() async throws -> [Announcement] {
        try await client.announcements(
            unitId: account.unit.id,
            pupilId: account.pupil.id
        )
    }

    func luckyNumber(day: Date) async throws -> Int? {
        let value = try await client.luckyNumber(
            pupilId: account.pupil.id,
            constituentId: account.constituentUnit.id,
            day: VulcanDate.dateString(day)
        )
        return value?.number
    }
}
