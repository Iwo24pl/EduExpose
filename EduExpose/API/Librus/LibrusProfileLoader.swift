import Foundation

/// Builds the provider-neutral `Account` the screens already understand.
///
/// `Me.Account` is the login owner (the parent on a parent login) and
/// `Me.User` is the student. Always prefer `User` for the child's name.
struct LibrusProfileLoader: Sendable {
    let client: LibrusAPIClient

    func load() async throws -> Account {
        let envelope = try await client.me()
        guard let me = envelope.me else {
            throw LibrusError.unexpectedResponse
        }

        let loginAccount = me.account
        let student = me.user
        let studentID = student?.id ?? loginAccount?.userId

        var school: LibrusSchool?
        if let envelope = try? await client.schools() {
            school = envelope.school
        }
        var schoolClass: LibrusClass?
        if let envelope = try? await client.classes() {
            schoolClass = envelope.schoolClass
        }
        var userRecord: LibrusUser?
        if let studentID {
            if let envelope = try? await client.user(id: studentID) {
                userRecord = envelope.user
            }
        }

        let firstName = student?.firstName ?? loginAccount?.firstName ?? "Uczeń"
        let lastName = student?.lastName ?? loginAccount?.lastName ?? ""
        let schoolName = trimmed(school?.name) ?? "Librus"
        let schoolID = (loginAccount?.schoolId
            ?? school?.id
            ?? schoolClass?.unitId)?.stableInt ?? 0

        let fallback = LibrusDate.schoolYearStrings(around: Date())
        let start = validDay(schoolClass?.beginSchoolYear, fallback: fallback.start)
        let mid = validDay(schoolClass?.endFirstSemester, fallback: fallback.mid)
        let end = validDay(schoolClass?.endSchoolYear, fallback: fallback.end)
        let today = LibrusDate.todayString()
        let currentPeriod = today <= mid ? 1 : 2

        let number = trimmed(schoolClass?.number)
        let symbol = trimmed(schoolClass?.symbol)
        let classLabel: String? = {
            switch (number, symbol) {
            case let (number?, symbol?):
                return number + symbol
            case let (number?, nil):
                return number
            case let (nil, symbol?):
                return symbol
            default:
                return nil
            }
        }()

        let pupil = Pupil(
            id: studentID?.stableInt ?? 0,
            firstName: firstName,
            secondName: nil,
            surname: lastName
        )

        let unit = SchoolUnit(
            id: schoolID,
            symbol: "LIBRUS",
            short: String(schoolName.prefix(10)),
            restURL: "librus",
            name: schoolName,
            displayName: schoolName
        )

        let periods = [
            Period(
                id: 1,
                level: 1,
                number: 1,
                startAt: start,
                endAt: mid,
                current: currentPeriod == 1,
                last: false
            ),
            Period(
                id: 2,
                level: 1,
                number: 2,
                startAt: mid,
                endAt: end,
                current: currentPeriod == 2,
                last: true
            )
        ]

        let journal = Journal(
            id: schoolClass?.id?.stableInt ?? 0,
            startAt: start,
            endAt: end,
            pupilNumber: userRecord?.classRegisterNumber?.int
        )

        return Account(
            classDisplay: classLabel,
            infoDisplay: "Librus",
            unit: unit,
            constituentUnit: ConstituentUnit(
                id: schoolID,
                short: "LIBRUS",
                name: schoolName
            ),
            pupil: pupil,
            periods: periods,
            journal: journal,
            messageBox: nil
        )
    }

    private func validDay(_ raw: String?, fallback: String) -> String {
        guard let raw, raw.count >= 10 else { return fallback }
        let value = String(raw.prefix(10))
        return LibrusDate.date(fromDay: value) == nil ? fallback : value
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
