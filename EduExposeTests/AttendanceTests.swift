import Foundation
import Testing

@testable import EduExpose

struct AttendanceDecodingTests {
    @Test("Decodes monthly presence statistics")
    func decodesMonthStats() throws {
        let json = """
        [{
          "PeriodId": 1,
          "Month": 10,
          "PresencePercentage": 96.0,
          "Absences": 2,
          "AbsencesJustified": 1,
          "LateArrivals": 1,
          "LateArrivalsJustified": 0,
          "Exemptions": 0,
          "AbsencesDueToSchool": 1
        }]
        """

        let stats = try JSONDecoder.vulcan().decode(
            [PresenceMonthStats].self,
            from: Data(json.utf8)
        )
        let month = try #require(stats.first)

        #expect(month.month == 10)
        #expect(month.percentage == 96)
        #expect(month.absences == 2)
        #expect(month.absencesJustified == 1)
        #expect(month.lateArrivals == 1)
        #expect(month.absencesDueToSchool == 1)
    }

    @Test("Decodes subject statistics")
    func decodesSubjectStats() throws {
        let json = """
        [{
          "PeriodId": 1,
          "SubjectId": 7,
          "SubjectName": "Matematyka",
          "PresencePercentage": 90.0,
          "Absences": 2,
          "AbsencesJustified": 1,
          "LateArrivals": 1,
          "LateArrivalsJustified": 0,
          "Exemptions": 0,
          "AbsencesDueToSchool": 0
        }]
        """

        let stats = try JSONDecoder.vulcan().decode(
            [PresenceSubjectStats].self,
            from: Data(json.utf8)
        )
        let subject = try #require(stats.first)

        #expect(subject.subjectName == "Matematyka")
        #expect(subject.percentage == 90)
        #expect(subject.lateArrivals == 1)
    }

    @Test("Decodes an attendance entry with its type and timeslot")
    func decodesEntry() throws {
        let json = """
        [{
          "Id": 1,
          "PresenceType": {
            "Id": 3,
            "Symbol": "nb",
            "Name": "Nieobecność",
            "CategoryId": 1,
            "CategoryName": "Nieobecności",
            "Position": 1,
            "Presence": false,
            "Absence": true,
            "LegalAbsence": false,
            "Late": false,
            "AbsenceJustified": false,
            "Removed": false
          },
          "DayAt": "2026-10-12",
          "TimeSlot": {
            "Id": 2,
            "Start": "08:55:00",
            "End": "09:40:00",
            "Display": "08:55 - 09:40",
            "Position": 2
          },
          "IdWeakRef": 123,
          "Type": 2
        }]
        """

        let entries = try JSONDecoder.vulcan().decode(
            [PresenceExtra].self,
            from: Data(json.utf8)
        )
        let entry = try #require(entries.first)

        #expect(entry.id == 1)
        #expect(entry.dayAt == "2026-10-12")
        #expect(entry.presenceType?.name == "Nieobecność")
        #expect(entry.presenceType?.absence == true)
        #expect(entry.timeSlot.start == "08:55:00")
        #expect(entry.idWeakRef == 123)
        #expect(entry.type == 2)
    }
}

struct AttendanceMathTests {
    @Test("Normalizes both percentage scales")
    func normalizesPercentage() {
        #expect(AttendanceMath.normalizedPercentage(0.96) == 96)
        #expect(AttendanceMath.normalizedPercentage(1.0) == 100)
        #expect(AttendanceMath.normalizedPercentage(96) == 96)
        #expect(AttendanceMath.normalizedPercentage(0) == 0)
    }

    @Test("Formats percentages for Polish readers")
    func formatsPercentage() {
        #expect(AttendanceMath.percentageText(96) == "96%")
        #expect(AttendanceMath.percentageText(95.5) == "95,5%")
        #expect(AttendanceMath.percentageText(0.96) == "96%")
    }

    @Test("Uses Polish month names")
    func monthNames() {
        #expect(AttendanceLabels.monthName(9) == "Wrzesień")
        #expect(AttendanceLabels.monthName(10) == "Październik")
        #expect(AttendanceLabels.monthName(13) == "13")
    }

    @Test("Resolves month years across a school year")
    func monthYears() {
        let period = Period(
            id: 1,
            level: nil,
            number: 1,
            startAt: "2025-09-01",
            endAt: "2026-06-30",
            current: true,
            last: false
        )

        #expect(AttendanceLabels.monthTitle(10, in: period) == "Październik 2025")
        #expect(AttendanceLabels.monthTitle(1, in: period) == "Styczeń 2026")
    }
}

struct AttendanceSnapshotTests {
    private func period() -> Period {
        Period(
            id: 1,
            level: nil,
            number: 1,
            startAt: "2025-09-01",
            endAt: "2026-06-30",
            current: true,
            last: false
        )
    }

    private func month(
        _ number: Int,
        percentage: Double = 100,
        absences: Int = 0,
        justified: Int = 0,
        late: Int = 0,
        lateJustified: Int = 0,
        exemptions: Int = 0,
        school: Int = 0
    ) -> PresenceMonthStats {
        PresenceMonthStats(
            periodId: 1,
            month: number,
            presencePercentage: percentage,
            absences: absences,
            absencesJustified: justified,
            lateArrivals: late,
            lateArrivalsJustified: lateJustified,
            exemptions: exemptions,
            absencesDueToSchool: school
        )
    }

    private func type(
        id: Int,
        name: String = "Nieobecność",
        presence: Bool = false,
        absence: Bool = true,
        legalAbsence: Bool = false,
        late: Bool = false,
        justified: Bool = false,
        removed: Bool = false
    ) -> PresenceType {
        PresenceType(
            id: id,
            symbol: "x",
            name: name,
            categoryId: 1,
            categoryName: "Frekwencja",
            position: 1,
            presence: presence,
            absence: absence,
            legalAbsence: legalAbsence,
            late: late,
            absenceJustified: justified,
            removed: removed
        )
    }

    private func entry(
        _ id: Int,
        day: String,
        start: String = "08:00:00",
        type: PresenceType?
    ) -> PresenceExtra {
        PresenceExtra(
            id: id,
            presenceType: type,
            dayAt: day,
            timeSlot: Timeslot(
                id: id,
                start: start,
                end: "08:45:00",
                display: nil,
                position: 1
            ),
            idWeakRef: nil,
            type: 2
        )
    }

    @Test("Sums counts and derives unjustified absences")
    func totals() {
        let snapshot = AttendanceSnapshot(
            period: period(),
            months: [
                month(9, absences: 2, justified: 1, late: 1, exemptions: 1, school: 1),
                month(10, absences: 1, late: 2, lateJustified: 1)
            ],
            subjects: [],
            entries: []
        )

        let totals = snapshot.totals
        #expect(totals.absences == 3)
        #expect(totals.absencesJustified == 1)
        #expect(totals.unjustified == 2)
        #expect(totals.lateArrivals == 3)
        #expect(totals.lateArrivalsJustified == 1)
        #expect(totals.exemptions == 1)
        #expect(totals.schoolAbsences == 1)
    }

    @Test("Orders months across the school-year boundary")
    func chronologicalMonths() {
        let snapshot = AttendanceSnapshot(
            period: period(),
            months: [month(1), month(9), month(10)],
            subjects: [],
            entries: []
        )

        #expect(snapshot.sortedMonths.map(\.month) == [9, 10, 1])
        #expect(snapshot.latestMonth?.month == 1)
    }

    @Test("Sorts subjects with the lowest attendance first")
    func sortsSubjects() {
        let subjects = [100.0, 90.0, 95.0].map { percentage in
            PresenceSubjectStats(
                periodId: 1,
                subjectId: Int(percentage),
                subjectName: "Przedmiot \(Int(percentage))",
                presencePercentage: percentage,
                absences: 0,
                absencesJustified: 0,
                lateArrivals: 0,
                lateArrivalsJustified: 0,
                exemptions: 0,
                absencesDueToSchool: 0
            )
        }
        let snapshot = AttendanceSnapshot(
            period: period(),
            months: [],
            subjects: subjects,
            entries: []
        )

        #expect(snapshot.sortedSubjects.map(\.percentage) == [90, 95, 100])
    }

    @Test("Filters corrections and groups entries by day")
    func filtersAndGroupsEntries() {
        let absence = type(id: 1, absence: true)
        let late = type(id: 2, name: "Spóźnienie", absence: false, late: true)
        let removed = type(id: 3, removed: true)
        let corrected = type(id: 4, presence: true, absence: false)
        let snapshot = AttendanceSnapshot(
            period: period(),
            months: [],
            subjects: [],
            entries: [
                entry(1, day: "2026-10-12", start: "10:00:00", type: absence),
                entry(2, day: "2026-10-12", start: "08:00:00", type: late),
                entry(3, day: "2026-10-13", type: removed),
                entry(4, day: "2026-10-13", type: corrected),
                entry(5, day: "2026-10-14", type: nil)
            ]
        )

        #expect(snapshot.visibleEntries.map(\.id).sorted() == [1, 2, 5])
        #expect(snapshot.entryDays.map(\.day) == ["2026-10-14", "2026-10-12"])
        #expect(snapshot.entryDays[1].entries.map(\.id) == [2, 1])
    }
}
