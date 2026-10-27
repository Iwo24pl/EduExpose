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
