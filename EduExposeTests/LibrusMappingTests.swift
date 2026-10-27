import Foundation
import Testing
@testable import EduExpose

@Suite("Librus decoding and mapping")
struct LibrusMappingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.vulcan().decode(T.self, from: Data(json.utf8))
    }

    @Test("Me uses User as the student and Account as the login owner")
    func decodesMe() throws {
        let json = """
        {"Me":{"Account":{"Id":10,"UserId":20,"FirstName":"Anna","LastName":"Nowak","SchoolId":3},
        "User":{"Id":20,"FirstName":"Ola","LastName":"Kowalska"}}}
        """
        let envelope = try decode(LibrusMeEnvelope.self, json)
        #expect(envelope.me?.account?.firstName == "Anna")
        #expect(envelope.me?.user?.firstName == "Ola")
        #expect(envelope.me?.user?.id?.stableInt == 20)
    }

    @Test("The class envelope decodes even though Class is a keyword")
    func decodesClass() throws {
        let json = """
        {"Class":{"Id":7,"Number":"7","Symbol":"d","BeginSchoolYear":"2026-09-01",
        "EndFirstSemester":"2027-01-31","EndSchoolYear":"2027-06-30"}}
        """
        let envelope = try decode(LibrusClassesEnvelope.self, json)
        #expect(envelope.schoolClass?.number == "7")
        #expect(envelope.schoolClass?.symbol == "d")
        #expect(envelope.schoolClass?.beginSchoolYear == "2026-09-01")
    }

    @Test("Grades map to the existing model, including 4+ and comments")
    func mapsGrades() throws {
        let json = """
        {"Grades":[{"Id":1,"Grade":"4+","Subject":{"Id":10},"Category":{"Id":2},
        "Semester":1,"AddDate":"2026-09-01 10:00:00","Comments":[{"Id":5}]}]}
        """
        let envelope = try decode(LibrusGradesEnvelope.self, json)
        let mapped = LibrusMapper.grades(
            envelope.grades ?? [],
            subjects: [LibrusID("10"): "Matematyka"],
            categories: [
                LibrusID("2"): LibrusGradeCategory(
                    id: LibrusID("2"),
                    name: "Sprawdzian",
                    weight: LibrusNumber(raw: "2", value: 2)
                )
            ],
            comments: [LibrusID("5"): "Bardzo dobrze"]
        )

        #expect(mapped.count == 1)
        #expect(mapped.first?.display == "4+")
        #expect(mapped.first?.numericValue == 4.5)
        #expect(mapped.first?.comment == "Bardzo dobrze")
        #expect(mapped.first?.column.subject.name == "Matematyka")
        #expect(mapped.first?.column.periodId == 1)
        #expect(mapped.first?.column.weight == 2.0)
    }

    @Test("Grade values follow Librus plus/minus rules")
    func gradeValues() {
        #expect(LibrusMapper.parseGradeValue("4+") == 4.5)
        #expect(LibrusMapper.parseGradeValue("4-") == 3.75)
        #expect(LibrusMapper.parseGradeValue("5") == 5)
        #expect(LibrusMapper.parseGradeValue("bz") == nil)
        #expect(LibrusMapper.parseGradeValue("np") == nil)
    }

    @Test("Timetable maps the nested date → slot → lesson shape")
    func mapsTimetable() throws {
        let json = """
        {"Timetable":{"2026-09-01":[[],[{"LessonNo":"2","HourFrom":"08:55","HourTo":"09:40",
        "Subject":{"Id":"10"},"Teacher":{"Id":"100"},
        "Classroom":{"Id":12,"Name":"Sala 12","Symbol":"12"},"IsCanceled":false,
        "IsSubstitutionClass":false}]]}}
        """
        let envelope = try decode(LibrusTimetableEnvelope.self, json)
        let mapped = LibrusMapper.timetable(
            envelope.timetable ?? [:],
            subjects: [LibrusID("10"): "Matematyka"],
            users: [LibrusID("100"): "Jan Kowalski"],
            classrooms: [
                LibrusID("12"): LibrusClassroom(id: LibrusID("12"), name: "Sala 12", symbol: "12")
            ]
        )

        #expect(mapped.count == 1)
        #expect(mapped.first?.dateAt == "2026-09-01")
        #expect(mapped.first?.timeSlot.position == 2)
        #expect(mapped.first?.effectiveSubject?.name == "Matematyka")
        #expect(mapped.first?.effectiveTeacher?.displayName == "Jan Kowalski")
        #expect(mapped.first?.effectiveRoom?.code == "12")
    }

    @Test("A cancelled lesson is marked for the existing UI")
    func mapsCancelledLesson() throws {
        let json = """
        {"Timetable":{"2026-09-02":[[{"LessonNo":1,"HourFrom":"08:00","HourTo":"08:45",
        "Subject":{"Id":10},"IsCanceled":true,"IsSubstitutionClass":false}]]}}
        """
        let envelope = try decode(LibrusTimetableEnvelope.self, json)
        let mapped = LibrusMapper.timetable(
            envelope.timetable ?? [:],
            subjects: [LibrusID("10"): "Fizyka"],
            users: [:],
            classrooms: [:]
        )
        #expect(mapped.first?.isCanceled == true)
        #expect(mapped.first?.event == "Odwołana")
    }

    @Test("School notices keep their string id as a stable UI id")
    func mapsAnnouncements() throws {
        let json = """
        {"SchoolNotices":[{"Id":"LID-NBOARD-NOTICE-42","Subject":"Wycieczka",
        "Content":"Szczegóły","StartDate":"2026-09-01","EndDate":"2026-09-02",
        "CreationDate":"2026-08-30 12:00:00"}]}
        """
        let envelope = try decode(LibrusSchoolNoticesEnvelope.self, json)
        let mapped = LibrusMapper.announcements(envelope.schoolNotices ?? [])
        #expect(mapped.count == 1)
        #expect(mapped.first?.title == "Wycieczka")
        #expect(mapped.first?.content == "Szczegóły")
        #expect(mapped.first?.id != 0)
    }

    @Test("Homework maps topic, due date and attachments")
    func mapsHomework() throws {
        let json = """
        {"HomeWorkAssignments":[{"Id":1,"Date":"2026-09-01","DueDate":"2026-09-05",
        "Topic":"Zadanie","Text":"Treść","Teacher":{"Id":100},
        "HomeworkAssigmentFiles":[{"Name":"plik.pdf","Url":"https://example.invalid/plik.pdf"}]}]}
        """
        let envelope = try decode(LibrusHomeworkAssignmentsEnvelope.self, json)
        let mapped = LibrusMapper.homework(
            envelope.homeWorkAssignments ?? [],
            subjects: [:],
            users: [LibrusID("100"): "Jan Kowalski"]
        )
        #expect(mapped.count == 1)
        #expect(mapped.first?.content == "Zadanie\nTreść")
        #expect(mapped.first?.deadlineAt == "2026-09-05")
        #expect(mapped.first?.subject.name == "Szkoła")
        #expect(mapped.first?.attachments?.first?.name == "plik.pdf")
    }

    @Test("Disabled averages decode to no averages")
    func disabledAverages() throws {
        let envelope = try decode(LibrusAveragesEnvelope.self, #"{"Status":"Disabled"}"#)
        #expect(envelope.averages == nil)
    }

    @Test("Lucky number only applies to its own day")
    func luckyNumberDay() throws {
        let envelope = try decode(
            LibrusLuckyNumbersEnvelope.self,
            #"{"LuckyNumber":{"LuckyNumber":13,"LuckyNumberDay":"2026-09-08"}}"#
        )
        let dto = try #require(envelope.luckyNumber)
        #expect(LibrusMapper.luckyNumber(dto, day: "2026-09-08")?.number == 13)
        #expect(LibrusMapper.luckyNumber(dto, day: "2026-09-09") == nil)
    }

    @Test("Message bodies are base64 XML CDATA containing HTML")
    func messageBody() {
        let xml = "<Message><Content><![CDATA[<p>Hello<br>World</p>]]></Content></Message>"
        let base64 = Data(xml.utf8).base64EncodedString()
        let text = LibrusMessageBody.decode(base64)
        #expect(text.contains("Hello"))
        #expect(text.contains("World"))
        #expect(!text.contains("<p>"))
    }

    @Test("String ids become stable positive integers")
    func stableIds() {
        let first = LibrusID("LID-NBOARD-NOTICE-42").stableInt
        let second = LibrusID("LID-NBOARD-NOTICE-42").stableInt
        #expect(first == second)
        #expect(first >= 0)
        #expect(LibrusID("41999").stableInt == 41999)
    }
}
