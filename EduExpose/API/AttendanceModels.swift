import Foundation

// MARK: - Attendance

struct PresenceType: Codable, Identifiable, Sendable {
    let id: Int
    let symbol: String
    let name: String
    let categoryId: Int
    let categoryName: String
    let position: Int
    let presence: Bool
    let absence: Bool
    let legalAbsence: Bool
    let late: Bool
    let absenceJustified: Bool
    let removed: Bool

    /// A reason worth showing in the attendance list. Presence corrections and
    /// deleted entries are skipped.
    var isAttendanceEvent: Bool {
        !removed && (absence || late || legalAbsence || absenceJustified)
    }
}

struct PresenceExtra: Codable, Identifiable, Sendable {
    let id: Int
    let presenceType: PresenceType?
    let dayAt: String
    let timeSlot: Timeslot
    let idWeakRef: Int?
    let type: Int
}

struct PresenceMonthStats: Codable, Identifiable, Sendable {
    let periodId: Int
    let month: Int
    let presencePercentage: Double
    let absences: Int
    let absencesJustified: Int
    let lateArrivals: Int
    let lateArrivalsJustified: Int
    let exemptions: Int
    let absencesDueToSchool: Int

    var id: Int { month }

    /// `Month == 0` is the API's "od początku roku" aggregate, not January.
    var isYearSummary: Bool { month == 0 }

    var percentage: Double {
        AttendanceMath.normalizedPercentage(presencePercentage)
    }
}

struct PresenceSubjectStats: Codable, Identifiable, Sendable {
    let periodId: Int
    let subjectId: Int
    let subjectName: String
    let presencePercentage: Double
    let absences: Int
    let absencesJustified: Int
    let lateArrivals: Int
    let lateArrivalsJustified: Int
    let exemptions: Int
    let absencesDueToSchool: Int

    var id: Int { subjectId }

    var percentage: Double {
        AttendanceMath.normalizedPercentage(presencePercentage)
    }
}

struct AttendanceTotals: Equatable, Sendable {
    let absences: Int
    let absencesJustified: Int
    let lateArrivals: Int
    let lateArrivalsJustified: Int
    let exemptions: Int
    let schoolAbsences: Int

    var unjustified: Int {
        max(0, absences - absencesJustified)
    }

    var eventCount: Int {
        absences + lateArrivals + exemptions + schoolAbsences
    }
}

extension AttendanceTotals {
    init(month: PresenceMonthStats) {
        self.init(
            absences: month.absences,
            absencesJustified: month.absencesJustified,
            lateArrivals: month.lateArrivals,
            lateArrivalsJustified: month.lateArrivalsJustified,
            exemptions: month.exemptions,
            schoolAbsences: month.absencesDueToSchool
        )
    }

    init(months: [PresenceMonthStats]) {
        self.init(
            absences: months.reduce(0) { $0 + $1.absences },
            absencesJustified: months.reduce(0) { $0 + $1.absencesJustified },
            lateArrivals: months.reduce(0) { $0 + $1.lateArrivals },
            lateArrivalsJustified: months.reduce(0) { $0 + $1.lateArrivalsJustified },
            exemptions: months.reduce(0) { $0 + $1.exemptions },
            schoolAbsences: months.reduce(0) { $0 + $1.absencesDueToSchool }
        )
    }

    init(subjects: [PresenceSubjectStats]) {
        self.init(
            absences: subjects.reduce(0) { $0 + $1.absences },
            absencesJustified: subjects.reduce(0) { $0 + $1.absencesJustified },
            lateArrivals: subjects.reduce(0) { $0 + $1.lateArrivals },
            lateArrivalsJustified: subjects.reduce(0) { $0 + $1.lateArrivalsJustified },
            exemptions: subjects.reduce(0) { $0 + $1.exemptions },
            schoolAbsences: subjects.reduce(0) { $0 + $1.absencesDueToSchool }
        )
    }

    /// Fallback when the statistics payload only carries a percentage.
    init(entries: [PresenceExtra]) {
        var absences = 0
        var justified = 0
        var late = 0
        var lateJustified = 0

        for entry in entries {
            guard let type = entry.presenceType else { continue }
            if type.absence {
                absences += 1
            }
            if type.late {
                late += 1
                if type.absenceJustified {
                    lateJustified += 1
                }
            }
            if type.absenceJustified {
                justified += 1
            }
        }

        self.init(
            absences: absences,
            absencesJustified: justified,
            lateArrivals: late,
            lateArrivalsJustified: lateJustified,
            exemptions: 0,
            schoolAbsences: 0
        )
    }
}

struct AttendanceDay: Identifiable, Sendable {
    let day: String
    let entries: [PresenceExtra]

    var id: String { day }
}

struct AttendanceSnapshot: Sendable {
    let period: Period
    let months: [PresenceMonthStats]
    let subjects: [PresenceSubjectStats]
    let entries: [PresenceExtra]

    /// Chronological order, not numeric month order: a school year runs from
    /// September to June, so January belongs to the next calendar year.
    /// The `Month == 0` aggregate is kept out of the month list.
    var sortedMonths: [PresenceMonthStats] {
        months
            .filter { !$0.isYearSummary }
            .sorted { left, right in
                let leftYear = AttendanceLabels.year(for: left.month, in: period) ?? 0
                let rightYear = AttendanceLabels.year(for: right.month, in: period) ?? 0
                if leftYear != rightYear {
                    return leftYear < rightYear
                }
                return left.month < right.month
            }
    }

    var yearSummary: PresenceMonthStats? {
        months.first { $0.isYearSummary }
    }

    /// The aggregate first, then the individual months.
    var displayMonths: [PresenceMonthStats] {
        (yearSummary.map { [$0] } ?? []) + sortedMonths
    }

    var latestMonth: PresenceMonthStats? {
        sortedMonths.last
    }

    /// Subjects with the lowest attendance first, so problems are visible.
    var sortedSubjects: [PresenceSubjectStats] {
        subjects.sorted { left, right in
            if left.percentage != right.percentage {
                return left.percentage < right.percentage
            }
            return left.subjectName.localizedStandardCompare(right.subjectName) == .orderedAscending
        }
    }

    /// Prefer the server's year aggregate, but fill any counter the statistics
    /// leave at zero from the detailed entries (some deployments return the
    /// percentage only in the year row).
    var totals: AttendanceTotals {
        let stats: AttendanceTotals
        if let yearSummary, AttendanceTotals(month: yearSummary).eventCount > 0 {
            stats = AttendanceTotals(month: yearSummary)
        } else {
            stats = AttendanceTotals(months: sortedMonths)
        }

        let detailed = AttendanceTotals(entries: visibleEntries)
        let subjectTotals = AttendanceTotals(subjects: subjects)
        return AttendanceTotals(
            absences: fill(stats.absences, from: max(subjectTotals.absences, detailed.absences)),
            absencesJustified: fill(stats.absencesJustified, from: max(subjectTotals.absencesJustified, detailed.absencesJustified)),
            lateArrivals: fill(stats.lateArrivals, from: max(subjectTotals.lateArrivals, detailed.lateArrivals)),
            lateArrivalsJustified: fill(stats.lateArrivalsJustified, from: max(subjectTotals.lateArrivalsJustified, detailed.lateArrivalsJustified)),
            exemptions: fill(stats.exemptions, from: max(subjectTotals.exemptions, detailed.exemptions)),
            schoolAbsences: fill(stats.schoolAbsences, from: max(subjectTotals.schoolAbsences, detailed.schoolAbsences))
        )
    }

    private func fill(_ value: Int, from fallback: Int) -> Int {
        value > 0 ? value : fallback
    }

    var visibleEntries: [PresenceExtra] {
        entries.filter { entry in
            guard let type = entry.presenceType else { return true }
            return type.isAttendanceEvent
        }
    }

    var entryDays: [AttendanceDay] {
        let grouped = Dictionary(grouping: visibleEntries) { entry in
            String(entry.dayAt.prefix(10))
        }
        return grouped
            .map { day, entries in
                AttendanceDay(
                    day: day,
                    entries: entries.sorted { $0.timeSlot.start < $1.timeSlot.start }
                )
            }
            .sorted { $0.day > $1.day }
    }
}

enum AttendanceMath {
    /// The API sends percentages as 0–100 on most deployments; a few send a
    /// 0–1 fraction. Treat a value in that range as a fraction.
    static func normalizedPercentage(_ raw: Double) -> Double {
        let value = raw > 0 && raw <= 1 ? raw * 100 : raw
        return min(max(value, 0), 100)
    }

    static func percentageText(_ raw: Double) -> String {
        let value = normalizedPercentage(raw)
        guard value.rounded() != value else {
            return "\(Int(value))%"
        }
        let text = String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return "\(text)%"
    }
}

enum AttendanceLabels {
    static func monthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "\(month)" }
        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = 1
        guard let date = VulcanDate.calendar.date(from: components) else {
            return "\(month)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date).capitalized
    }

    /// The year a month belongs to inside a school-year period.
    static func year(for month: Int, in period: Period) -> Int? {
        guard let start = yearMonth(period.startAt) else { return nil }
        return month >= start.month ? start.year : start.year + 1
    }

    static func monthTitle(_ month: Int, in period: Period) -> String {
        if month == 0 {
            return "Od początku roku"
        }
        if let year = year(for: month, in: period) {
            return "\(monthName(month)) \(year)"
        }
        return monthName(month)
    }

    /// `2026/27` only for a period that spans the whole school year. A single
    /// semester keeps its "Okres N" label.
    static func schoolYear(in period: Period) -> String? {
        guard let start = yearMonth(period.startAt),
              let end = yearMonth(period.endAt),
              end.year > start.year,
              end.month >= 6 else {
            return nil
        }
        return "\(start.year)/" + String(format: "%02d", end.year % 100)
    }

    private static func yearMonth(_ raw: String) -> (year: Int, month: Int)? {
        let parts = raw
            .prefix(10)
            .split(separator: "-")
            .compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}
