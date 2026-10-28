import Foundation

/// Librus journal reads with conservative caching. Reference data changes
/// rarely and is kept for a day; user data is kept for a minute so switching
/// tabs does not hammer the API.
actor LibrusJournalService: JournalService {
    private let client: LibrusAPIClient

    private var subjectsCache: (at: Date, values: [LibrusID: String])?
    private var usersCache: (at: Date, values: [LibrusID: String])?
    private var classroomsCache: (at: Date, values: [LibrusID: LibrusClassroom])?
    private var gradeCategoriesCache: (at: Date, values: [LibrusID: LibrusGradeCategory])?
    private var gradeCommentsCache: (at: Date, values: [LibrusID: String])?
    private var homeworkCategoriesCache: (at: Date, values: [LibrusID: String])?
    private var noteCategoriesCache: (at: Date, values: [LibrusID: String])?
    private var lessonsCache: (at: Date, values: [LibrusID: LibrusID])?
    private var attendanceTypesCache: (at: Date, values: [LibrusAttendanceType])?

    private var gradesCache: [Int: (at: Date, values: [Grade])] = [:]
    private var timetableCache: [String: (at: Date, values: [Schedule])] = [:]

    init(session: LibrusSessionActor, trace: LibrusTrace = LibrusTrace()) {
        client = LibrusAPIClient(session: session, trace: trace)
    }

    // MARK: JournalService

    func grades(period: Period?) async throws -> [Grade] {
        let key = period?.number ?? 0
        if let cached = gradesCache[key],
           fresh(cached.at, LibrusConstants.userDataSourceLifetime) {
            return cached.values
        }

        let subjects = try await subjectMap()
        let categories = (try? await gradeCategoryMap()) ?? [:]
        let comments = (try? await commentMap()) ?? [:]
        let response = try await client.grades()
        let mapped = LibrusMapper.grades(
            response.grades ?? [],
            subjects: subjects,
            categories: categories,
            comments: comments
        )
        let filtered = period?.number.map { number in
            number == 0 ? mapped : mapped.filter { $0.column.periodId == number }
        } ?? mapped
        gradesCache[key] = (Date(), filtered)
        return filtered
    }

    func averages(period: Period?) async throws -> [GradeAverage] {
        do {
            let response = try await client.averages()
            guard let averages = response.averages else { return [] }
            let subjects = try await subjectMap()
            return LibrusMapper.averages(averages, subjects: subjects)
        } catch {
            if isUnavailable(error) { return [] }
            throw error
        }
    }

    func timetable(from: Date, to: Date) async throws -> [Schedule] {
        let fromDay = LibrusDate.dayString(from)
        let toDay = LibrusDate.dayString(to)
        if let cached = timetableCache[fromDay],
           fresh(cached.at, LibrusConstants.userDataSourceLifetime) {
            return cached.values
        }

        do {
            let weekStart = LibrusDate.dayString(LibrusDate.weekStart(from))
            let response = try await client.timetable(weekStart: weekStart)
            let subjects = try await subjectMap()
            let users = try await usersMap()
            let classrooms = try await classroomMap()
            let mapped = LibrusMapper.timetable(
                response.timetable ?? [:],
                subjects: subjects,
                users: users,
                classrooms: classrooms
            )
            let filtered = mapped.filter {
                LibrusDate.isDay($0.dateAt, between: fromDay, to: toDay)
            }
            timetableCache[fromDay] = (Date(), filtered)
            return filtered
        } catch {
            if isUnavailable(error) { return [] }
            throw error
        }
    }

    func exams(from: Date, to: Date) async throws -> [Exam] {
        do {
            let response = try await client.homeWorks()
            let categories = (try? await homeworkCategoryMap()) ?? [:]
            let subjects = try await subjectMap()
            let users = try await usersMap()
            let mapped = LibrusMapper.exams(
                response.homeWorks ?? [],
                categories: categories,
                subjects: subjects,
                users: users
            )
            let fromDay = LibrusDate.dayString(from)
            let toDay = LibrusDate.dayString(to)
            return mapped.filter {
                LibrusDate.isDay($0.deadlineAt, between: fromDay, to: toDay)
            }
        } catch {
            if isUnavailable(error) { return [] }
            throw error
        }
    }

    func homework(from: Date, to: Date) async throws -> [Homework] {
        do {
            let response = try await client.homeworkAssignments()
            let subjects = try await subjectMap()
            let users = try await usersMap()
            let mapped = LibrusMapper.homework(
                response.homeWorkAssignments ?? [],
                subjects: subjects,
                users: users
            )
            let fromDay = LibrusDate.dayString(from)
            let toDay = LibrusDate.dayString(to)
            return mapped.filter {
                LibrusDate.isDay($0.deadlineAt, between: fromDay, to: toDay)
            }
        } catch {
            if isUnavailable(error) { return [] }
            throw error
        }
    }

    func notes() async throws -> [Note] {
        do {
            let response = try await client.notes()
            let categories = (try? await noteCategoryMap()) ?? [:]
            let users = try await usersMap()
            return LibrusMapper.notes(
                response.notes ?? [],
                categories: categories,
                users: users
            )
        } catch {
            if isUnavailable(error) { return [] }
            throw error
        }
    }

    func announcements() async throws -> [Announcement] {
        do {
            let response = try await client.schoolNotices()
            return LibrusMapper.announcements(response.schoolNotices ?? [])
        } catch {
            if isUnavailable(error) { return [] }
            throw error
        }
    }

    func luckyNumber(day: Date) async throws -> Int? {
        do {
            let response = try await client.luckyNumbers()
            guard let dto = response.luckyNumber else { return nil }
            return LibrusMapper.luckyNumber(dto, day: LibrusDate.dayString(day))?.number
        } catch {
            if isUnavailable(error) { return nil }
            throw error
        }
    }

    func attendance(period: Period) async throws -> AttendanceSnapshot {
        do {
            let attendanceResponse = try await client.attendances()
            let types = (try? await attendanceTypeList()) ?? []
            let subjects = try await subjectMap()
            let lessons = (try? await lessonSubjectMap()) ?? [:]
            return LibrusMapper.attendance(
                period: period,
                attendances: attendanceResponse.attendances ?? [],
                types: types,
                lessonSubjects: lessons,
                subjects: subjects
            )
        } catch {
            if isUnavailable(error) {
                return AttendanceSnapshot(
                    period: period,
                    months: [],
                    subjects: [],
                    entries: []
                )
            }
            throw error
        }
    }

    // MARK: Lookups

    private func subjectMap() async throws -> [LibrusID: String] {
        if let cached = subjectsCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.subjects()
        var values: [LibrusID: String] = [:]
        for subject in response.subjects ?? [] {
            values[subject.id] = subject.name
        }
        subjectsCache = (Date(), values)
        return values
    }

    private func usersMap() async throws -> [LibrusID: String] {
        if let cached = usersCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.users()
        var values: [LibrusID: String] = [:]
        for user in response.users ?? [] {
            guard let id = user.id else { continue }
            let name = [user.firstName, user.lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty {
                values[id] = name
            }
        }
        usersCache = (Date(), values)
        return values
    }

    private func classroomMap() async throws -> [LibrusID: LibrusClassroom] {
        if let cached = classroomsCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.classrooms()
        var values: [LibrusID: LibrusClassroom] = [:]
        for classroom in response.classrooms ?? [] {
            values[classroom.id] = classroom
        }
        classroomsCache = (Date(), values)
        return values
    }

    private func gradeCategoryMap() async throws -> [LibrusID: LibrusGradeCategory] {
        if let cached = gradeCategoriesCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.gradeCategories()
        var values: [LibrusID: LibrusGradeCategory] = [:]
        for category in response.categories ?? [] {
            values[category.id] = category
        }
        gradeCategoriesCache = (Date(), values)
        return values
    }

    private func commentMap() async throws -> [LibrusID: String] {
        if let cached = gradeCommentsCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.gradeComments()
        var values: [LibrusID: String] = [:]
        for comment in response.comments ?? [] {
            if let text = comment.text, !text.isEmpty {
                values[comment.id] = text
            }
        }
        gradeCommentsCache = (Date(), values)
        return values
    }

    private func homeworkCategoryMap() async throws -> [LibrusID: String] {
        if let cached = homeworkCategoriesCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.homeworkCategories()
        var values: [LibrusID: String] = [:]
        for category in response.categories ?? [] {
            if let name = category.name, !name.isEmpty {
                values[category.id] = name
            }
        }
        homeworkCategoriesCache = (Date(), values)
        return values
    }

    private func noteCategoryMap() async throws -> [LibrusID: String] {
        if let cached = noteCategoriesCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.noteCategories()
        var values: [LibrusID: String] = [:]
        for category in response.categories ?? [] {
            if let name = category.categoryName, !name.isEmpty {
                values[category.id] = name
            }
        }
        noteCategoriesCache = (Date(), values)
        return values
    }

    private func attendanceTypeList() async throws -> [LibrusAttendanceType] {
        if let cached = attendanceTypesCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.attendanceTypes()
        let values = response.types ?? []
        attendanceTypesCache = (Date(), values)
        return values
    }

    private func lessonSubjectMap() async throws -> [LibrusID: LibrusID] {
        if let cached = lessonsCache,
           fresh(cached.at, LibrusConstants.referenceDataLifetime) {
            return cached.values
        }
        let response = try await client.lessons()
        var values: [LibrusID: LibrusID] = [:]
        for lesson in response.lessons ?? [] {
            if let subject = lesson.subject?.id {
                values[lesson.id] = subject
            }
        }
        lessonsCache = (Date(), values)
        return values
    }

    // MARK: Helpers

    private func fresh(_ date: Date, _ ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(date) < ttl
    }

    private func isUnavailable(_ error: any Error) -> Bool {
        guard let error = error as? LibrusError else { return false }
        switch error {
        case .moduleUnavailable(_, _), .insufficientScopes(_):
            return true
        case .httpStatus(let status) where status == 403 || status == 404:
            return true
        default:
            return false
        }
    }
}
