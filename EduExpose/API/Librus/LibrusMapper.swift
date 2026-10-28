import Foundation

/// Pure mapping from Librus gateway DTOs to the models the existing screens
/// already use. Keeping this free of networking makes it fully testable
/// without an account.
enum LibrusMapper {
    // MARK: Grades

    static func grades(
        _ grades: [LibrusGrade],
        subjects: [LibrusID: String],
        categories: [LibrusID: LibrusGradeCategory],
        comments: [LibrusID: String]
    ) -> [Grade] {
        grades.map { grade in
            let category = grade.category.flatMap { categories[$0.id] }
            let subject = subject(
                grade.subject?.id,
                name: (grade.subject?.id).flatMap { subjects[$0] }
            )
            let comment = grade.comments?
                .compactMap { comments[$0.id] }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            return Grade(
                id: grade.id.stableInt,
                key: grade.id.raw,
                pupilId: nil,
                contentRaw: grade.grade,
                content: grade.grade,
                comment: comment?.isEmpty == true ? nil : comment,
                value: parseGradeValue(grade.grade),
                createdAt: grade.addDate,
                modifiedAt: nil,
                column: GradeColumn(
                    id: category?.id.stableInt ?? subject.id,
                    key: category?.id.raw,
                    periodId: grade.semester,
                    name: category?.name ?? "",
                    code: nil,
                    group: nil,
                    number: nil,
                    color: nil,
                    weight: category?.weight?.value,
                    subject: subject,
                    category: category.map {
                        GradeCategory(id: $0.id.stableInt, name: $0.name, code: nil)
                    }
                ),
                correctedGrade: nil
            )
        }
    }

    static func averages(
        _ averages: [String: LibrusNumber],
        subjects: [LibrusID: String]
    ) -> [GradeAverage] {
        averages.compactMap { entry in
            let id = LibrusID(entry.key)
            let number = entry.value
            guard let average = number.value.map(\.clean) ?? number.raw, !average.isEmpty else {
                return nil
            }
            return GradeAverage(
                id: id.stableInt,
                pupilId: nil,
                periodId: nil,
                subject: subject(id, name: subjects[id]),
                average: average,
                points: nil,
                scope: "Librus"
            )
        }
        .sorted { $0.subject.name < $1.subject.name }
    }

    /// `4+` is 4.5 and `4-` is 3.75 in Librus; non-numeric marks such as
    /// `bz` or `np` keep their text but have no numeric value.
    static func parseGradeValue(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), (0...6).contains(value) {
            return value
        }
        guard let first = normalized.first,
              let base = Double(String(first)),
              (1...6).contains(base) else {
            return nil
        }
        switch normalized.dropFirst() {
        case "+": return base + 0.5
        case "-": return base - 0.25
        default: return nil
        }
    }

    // MARK: Timetable

    static func timetable(
        _ timetable: [String: [[LibrusLesson]]],
        subjects: [LibrusID: String],
        users: [LibrusID: String],
        classrooms: [LibrusID: LibrusClassroom]
    ) -> [Schedule] {
        var result: [Schedule] = []

        for (date, slots) in timetable.sorted(by: { $0.key < $1.key }) {
            for (slotIndex, lessons) in slots.enumerated() {
                for lesson in lessons {
                    let position = lesson.lessonNo?.int ?? (slotIndex + 1)
                    let subjectID = lesson.subject?.id
                    let subject = subject(
                        subjectID,
                        name: subjectID.flatMap { subjects[$0] } ?? "Lekcja"
                    )
                    let teacherID = lesson.teacher?.id
                    let teacherName = teacherID.flatMap { users[$0] }
                    let classroomID = lesson.classroom?.id
                    let classroom = classroomID.flatMap { classrooms[$0] }
                    let roomName = classroom?.symbol ?? classroom?.name
                        ?? lesson.classroom?.symbol
                        ?? lesson.classroom?.name
                    let isCanceled = lesson.isCanceled == true
                    let isSubstitution = lesson.isSubstitutionClass == true
                    let slot = Timeslot(
                        id: position,
                        start: lesson.hourFrom ?? "",
                        end: lesson.hourTo ?? "",
                        display: nil,
                        position: position
                    )
                    let substitution: ScheduleSubstitution? = {
                        guard isCanceled || isSubstitution else { return nil }
                        return ScheduleSubstitution(
                            id: 0,
                            dateAt: lesson.orgDate,
                            pupilNote: nil,
                            reason: isSubstitution ? "Zastępstwo" : nil,
                            event: isCanceled ? "Odwołana" : nil,
                            room: nil,
                            timeSlot: nil,
                            subject: nil,
                            teacherPrimary: nil,
                            teacherAbsenceReasonId: nil,
                            teacherAbsenceEffectName: nil,
                            change: nil,
                            classAbsence: isCanceled,
                            noRoom: false,
                            description: lesson.substitutionNote
                        )
                    }()

                    result.append(Schedule(
                        id: stable("\(date)|\(position)|\(subjectID?.raw ?? "")"),
                        mergeChangeId: nil,
                        event: isCanceled ? "Odwołana" : nil,
                        dateAt: date,
                        room: roomName?.isEmpty == false
                            ? Room(
                                id: classroomID?.stableInt ?? subject.id,
                                code: roomName ?? "-"
                            )
                            : nil,
                        timeSlot: slot,
                        subject: subject,
                        teacherPrimary: employee(teacherID, name: teacherName),
                        substitution: substitution
                    ))
                }
            }
        }
        return result
    }

    // MARK: Agenda and homework

    static func exams(
        _ events: [LibrusAgendaEvent],
        categories: [LibrusID: String],
        subjects: [LibrusID: String],
        users: [LibrusID: String]
    ) -> [Exam] {
        events.map { event in
            let categoryName = (event.category?.id).flatMap { categories[$0] } ?? "Sprawdzian"
            let subjectID = event.subject?.id
            let subjectName = subjectID.flatMap { subjects[$0] } ?? "Szkoła"
            let creatorID = event.createdBy?.id
            return Exam(
                id: event.id.stableInt,
                key: event.id.raw,
                type: categoryName,
                typeId: nil,
                content: event.content ?? "",
                deadlineAt: day(event.date),
                createdAt: nil,
                subject: subject(subjectID, name: subjectName),
                creator: employee(creatorID, name: creatorID.flatMap { users[$0] })
            )
        }
    }

    static func homework(
        _ assignments: [LibrusHomeworkAssignment],
        subjects: [LibrusID: String],
        users: [LibrusID: String]
    ) -> [Homework] {
        assignments.compactMap { assignment in
            let deadline = day(assignment.dueDate)
            guard !deadline.isEmpty else { return nil }
            let subjectID = assignment.subject?.id
            let subjectName = subjectID.flatMap { subjects[$0] } ?? "Szkoła"
            let content = [assignment.topic, assignment.text]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let teacherID = assignment.teacher?.id
            let attachments = assignment.homeworkAssigmentFiles?
                .compactMap { file -> Attachment? in
                    guard let name = file.name, !name.isEmpty else { return nil }
                    return Attachment(name: name, link: file.url)
                }

            return Homework(
                id: assignment.id.stableInt,
                key: assignment.id.raw,
                content: content.isEmpty ? "Zadanie domowe" : content,
                isAnswerRequired: nil,
                dateAt: assignment.date.map { day($0) },
                deadlineAt: deadline,
                subject: subject(subjectID, name: subjectName),
                creator: employee(teacherID, name: teacherID.flatMap { users[$0] }),
                attachments: attachments
            )
        }
    }

    // MARK: Notes and announcements

    static func notes(
        _ notes: [LibrusNote],
        categories: [LibrusID: String],
        users: [LibrusID: String]
    ) -> [Note] {
        notes.map { note in
            let categoryID = note.category?.id
            let teacherID = note.teacher?.id
            return Note(
                id: note.id.stableInt,
                positive: note.positive == 1,
                validAt: day(note.date),
                modifiedAt: nil,
                category: categoryID.map {
                    NoteCategory(
                        id: $0.stableInt,
                        name: categories[$0] ?? "Notatka",
                        type: nil
                    )
                },
                content: note.text ?? "",
                points: nil,
                creator: employee(teacherID, name: teacherID.flatMap { users[$0] })
            )
        }
    }

    static func announcements(_ notices: [LibrusSchoolNotice]) -> [Announcement] {
        notices.map { notice in
            let title = notice.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Announcement(
                id: notice.id.stableInt,
                idUnit: nil,
                title: title?.isEmpty == false ? (title ?? "Ogłoszenie") : "Ogłoszenie",
                content: MailText.plainText(from: notice.content ?? ""),
                category: nil,
                from: notice.startDate,
                to: notice.endDate,
                sender: nil,
                createdAt: notice.creationDate,
                attachments: nil
            )
        }
    }

    // MARK: Lucky number

    static func luckyNumber(_ dto: LibrusLuckyNumber, day requested: String) -> LuckyNumber? {
        guard let number = dto.luckyNumber else { return nil }
        let day = String((dto.luckyNumberDay ?? "").prefix(10))
        guard !day.isEmpty, day == requested else { return nil }
        return LuckyNumber(day: day, number: number)
    }

    // MARK: Attendance

    /// Librus exposes raw attendance records, not the per-month and
    /// per-subject statistics VULCAN returns. The derived numbers use the
    /// same semantics as the attendance screen: a record whose type is an
    /// absence lowers the percentage; late arrivals remain present.
    static func attendance(
        period: Period,
        attendances: [LibrusAttendance],
        types: [LibrusAttendanceType],
        lessonSubjects: [LibrusID: LibrusID],
        subjects: [LibrusID: String]
    ) -> AttendanceSnapshot {
        let typeMap = Dictionary(
            grouping: types,
            by: { $0.id }
        ).compactMapValues { $0.first }
        let filtered = attendances.filter { record in
            guard let number = period.number, number != 0 else { return true }
            if let semester = record.semester {
                return semester == number
            }
            guard let day = record.date.map({ String($0.prefix(10)) }) else { return false }
            return LibrusDate.isDay(
                day,
                between: String(period.startAt.prefix(10)),
                to: String(period.endAt.prefix(10))
            )
        }

        let entries = filtered.map { record -> PresenceExtra in
            let type = record.type.flatMap { typeMap[$0.id] }
            let presence = presenceType(type)
            let position = record.lessonNo ?? 0
            return PresenceExtra(
                id: record.id.stableInt,
                presenceType: presence,
                dayAt: String((record.date ?? "").prefix(10)),
                timeSlot: Timeslot(
                    id: position,
                    start: "",
                    end: "",
                    display: position > 0 ? "Lekcja \(position)" : nil,
                    position: position
                ),
                idWeakRef: record.lesson?.id.stableInt,
                type: presence?.id ?? 0
            )
        }

        let months = monthStats(
            entries: entries,
            period: period,
            includeYearSummary: true
        )
        let subjectsStats = subjectStats(
            filtered: filtered,
            entries: entries,
            period: period,
            lessonSubjects: lessonSubjects,
            subjects: subjects
        )

        return AttendanceSnapshot(
            period: period,
            months: months,
            subjects: subjectsStats,
            entries: entries
        )
    }

    static func presenceType(_ type: LibrusAttendanceType?) -> PresenceType? {
        guard let type else { return nil }
        let name = type.name ?? type.short ?? "Frekwencja"
        let lower = name.lowercased()
        let absence = lower.contains("nieobecn")
        let late = lower.contains("spóźn") || lower.contains("spozn")
        let justified = lower.contains("uspr")
            || lower.contains("uspraw")
            || lower.contains("zwoln")
        let legal = lower.contains("zwoln") || lower.contains("legal")
        let presence = !absence && (type.isPresenceKind == true || lower.contains("obecn"))

        return PresenceType(
            id: type.id.stableInt,
            symbol: type.short ?? String(name.prefix(4)),
            name: name,
            categoryId: 0,
            categoryName: absence ? "Nieobecność" : (late ? "Spóźnienie" : "Frekwencja"),
            position: type.id.stableInt,
            presence: presence,
            absence: absence,
            legalAbsence: legal,
            late: late,
            absenceJustified: justified,
            removed: false
        )
    }

    private static func monthStats(
        entries: [PresenceExtra],
        period: Period,
        includeYearSummary: Bool
    ) -> [PresenceMonthStats] {
        let grouped = Dictionary(grouping: entries) { entry -> Int in
            let day = String(entry.dayAt.prefix(10))
            let parts = day.split(separator: "-")
            return parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
        }

        var result = grouped
            .filter { $0.key > 0 }
            .map { month, items in
                stats(period: period, month: month, entries: items)
            }
            .sorted { $0.month < $1.month }

        if includeYearSummary {
            result.insert(stats(period: period, month: 0, entries: entries), at: 0)
        }
        return result
    }

    private static func subjectStats(
        filtered: [LibrusAttendance],
        entries: [PresenceExtra],
        period: Period,
        lessonSubjects: [LibrusID: LibrusID],
        subjects: [LibrusID: String]
    ) -> [PresenceSubjectStats] {
        let entriesByID = Dictionary(
            grouping: entries,
            by: { $0.id }
        ).compactMapValues { $0.first }
        var grouped: [LibrusID: [PresenceExtra]] = [:]

        for record in filtered {
            guard let entry = entriesByID[record.id.stableInt] else { continue }
            let subjectID = record.lesson?.id.flatMap { lessonSubjects[$0] }
            grouped[subjectID ?? LibrusID("0"), default: []].append(entry)
        }

        return grouped.map { subjectID, items in
            let base = stats(period: period, month: 0, entries: items)
            return PresenceSubjectStats(
                periodId: period.id,
                subjectId: subjectID.stableInt,
                subjectName: subjects[subjectID] ?? "Inne",
                presencePercentage: base.presencePercentage,
                absences: base.absences,
                absencesJustified: base.absencesJustified,
                lateArrivals: base.lateArrivals,
                lateArrivalsJustified: base.lateArrivalsJustified,
                exemptions: base.exemptions,
                absencesDueToSchool: base.absencesDueToSchool
            )
        }
        .sorted { $0.subjectName < $1.subjectName }
    }

    private static func stats(
        period: Period,
        month: Int,
        entries: [PresenceExtra]
    ) -> PresenceMonthStats {
        var absences = 0
        var justified = 0
        var late = 0
        var lateJustified = 0
        var exemptions = 0
        var present = 0

        for entry in entries {
            guard let type = entry.presenceType else { continue }
            if type.absence {
                absences += 1
                if type.absenceJustified { justified += 1 }
            } else {
                present += 1
            }
            if type.late {
                late += 1
                if type.absenceJustified { lateJustified += 1 }
            }
            if type.legalAbsence {
                exemptions += 1
            }
        }

        let total = max(entries.count, 1)
        let percentage = Double(present) / Double(total) * 100

        return PresenceMonthStats(
            periodId: period.id,
            month: month,
            presencePercentage: percentage,
            absences: absences,
            absencesJustified: justified,
            lateArrivals: late,
            lateArrivalsJustified: lateJustified,
            exemptions: exemptions,
            absencesDueToSchool: 0
        )
    }

    // MARK: Helpers

    private static func subject(_ id: LibrusID?, name: String?) -> Subject {
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Subject(
            id: id?.stableInt ?? 0,
            key: id?.raw,
            name: title?.isEmpty == false ? (title ?? "Przedmiot") : "Przedmiot",
            kod: nil,
            position: nil
        )
    }

    private static func employee(_ id: LibrusID?, name: String?) -> Employee? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        return Employee(
            id: id?.stableInt ?? 0,
            surname: parts.count > 1 ? parts[1] : "",
            name: parts.first ?? name,
            displayName: name
        )
    }

    private static func day(_ raw: String?) -> String {
        String((raw ?? "").prefix(10))
    }

    private static func stable(_ text: String) -> Int {
        LibrusID.stableHash(text)
    }
}
