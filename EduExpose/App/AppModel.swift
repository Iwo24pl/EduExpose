import Foundation
import Observation
import Security

struct StartSnapshot: Sendable {
    let firstName: String
    let lucky: Int?
    let grades: [Grade]
    let exams: [Exam]
    let homework: [Homework]
}

struct GradesSnapshot: Sendable {
    let grades: [Grade]
    let averages: [GradeAverage]
}

struct UpdateInfo: Sendable {
    let version: String
    let url: URL
    let isNewer: Bool
}

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching
        case login
        case students
        case dashboard
    }

    var phase: Phase = .launching
    var students: [StoredStudent] = []
    var activeID: String?
    var pending: [StoredStudent] = []
    var selected: Set<String> = []
    var isBusy = false
    var isAddingAccount = false
    var errorMessage: String?
    var updateInfo: UpdateInfo?
    var mailTrace: [MailTraceEvent] = []

    let session: URLSession
    private var clients: [String: HebeClient] = [:]
    @ObservationIgnored private var cachedMailService: (studentID: String, service: any MailService)?
    @ObservationIgnored private var mailCookies: [String: [CookieSnapshot]] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    var activeStudent: StoredStudent? {
        students.first { $0.id == activeID }
    }

    var activeAccount: Account? {
        activeStudent?.account
    }

    // MARK: Session lifecycle

    func bootstrap() async {
        guard phase == .launching else { return }
        if let data = try? KeychainStore.load(),
           let stored = try? JSONDecoder().decode([StoredStudent].self, from: data) {
            students = stored
            for student in stored {
                clients[student.id] = HebeClient(student: student, session: session)
            }
            activeID = stored.first(where: { $0.isEnabled })?.id ?? stored.first?.id
        }
        phase = students.isEmpty ? .login : .dashboard
    }

    func login(login rawLogin: String, password: String) async {
        let login = rawLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty, !password.isEmpty else {
            errorMessage = "Podaj login i hasło."
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            let found = try await PrometheusLoginService(session: session)
                .signIn(login: login, password: password)
            let portalCookies = CookieSnapshot.capturePortal(
                HTTPCookieStorage.shared.cookies ?? []
            )
            await MailTraceStore.shared.record(
                "login.cookies",
                "count=\(portalCookies.count)"
            )
            // A new portal login invalidates cookies held by other accounts.
            mailCookies = [:]
            for student in found {
                mailCookies[student.id] = portalCookies
            }
            cachedMailService = nil
            pending = found
            selected = Set(found.map(\.id))
            phase = .students
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
    }

    func confirmSelection() {
        let chosen = pending.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else {
            errorMessage = "Wybierz co najmniej jednego ucznia."
            return
        }
        var merged = students
        for student in chosen {
            if let index = merged.firstIndex(where: { $0.id == student.id }) {
                merged[index] = student
            } else {
                merged.append(student)
            }
            clients[student.id] = HebeClient(student: student, session: session)
        }
        cachedMailService = nil
        students = merged.sorted { $0.account.displayName < $1.account.displayName }
        activeID = chosen.first?.id ?? activeID
        pending = []
        selected = []
        isAddingAccount = false
        errorMessage = nil
        save()
        phase = .dashboard
    }

    func beginAddAccount() {
        isAddingAccount = true
        errorMessage = nil
        phase = .login
    }

    func cancelAddAccount() {
        isAddingAccount = false
        errorMessage = nil
        phase = students.isEmpty ? .login : .dashboard
    }

    func selectStudent(_ id: String) {
        guard students.contains(where: { $0.id == id }) else { return }
        if activeID != id {
            cachedMailService = nil
        }
        activeID = id
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = students.firstIndex(where: { $0.id == id }) else { return }
        students[index].isEnabled = enabled
        if enabled {
            activeID = id
        } else if activeID == id {
            activeID = students.first(where: { $0.isEnabled })?.id
        }
        save()
    }

    func removeStudent(_ id: String) {
        students.removeAll { $0.id == id }
        clients[id] = nil
        mailCookies[id] = nil
        if cachedMailService?.studentID == id {
            cachedMailService = nil
        }
        if activeID == id {
            activeID = students.first(where: { $0.isEnabled })?.id ?? students.first?.id
        }
        save()
        if students.isEmpty {
            phase = .login
        }
    }

    func logout() {
        KeychainStore.delete()
        students = []
        clients = [:]
        cachedMailService = nil
        mailCookies = [:]
        activeID = nil
        pending = []
        selected = []
        errorMessage = nil
        phase = .login
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    private func save() {
        do {
            try KeychainStore.save(JSONEncoder().encode(students))
        } catch {
            errorMessage = "Nie udało się zapisać sesji w Keychain."
        }
    }

    // MARK: Loading

    private func context() throws -> (StoredStudent, Account, HebeClient, Period) {
        guard let id = activeID,
              let student = students.first(where: { $0.id == id }),
              let client = clients[id] else {
            throw VulcanError.noStudent
        }
        guard let period = student.account.currentPeriod else {
            throw VulcanError.noPeriod
        }
        return (student, student.account, client, period)
    }

    func loadStart() async throws -> StartSnapshot {
        let (_, account, client, period) = try context()
        let today = Date()
        let from = VulcanDate.dateString(VulcanDate.addDays(today, -14))
        let to = VulcanDate.dateString(VulcanDate.addDays(today, 14))

        async let gradesTask = client.grades(
            unitId: account.unit.id,
            pupilId: account.pupil.id,
            periodId: period.id
        )
        async let examsTask = client.exams(
            pupilId: account.pupil.id,
            from: from,
            to: to
        )
        async let homeworkTask = client.homework(
            pupilId: account.pupil.id,
            from: from,
            to: to
        )
        let lucky = try? await client.luckyNumber(
            pupilId: account.pupil.id,
            constituentId: account.constituentUnit.id,
            day: VulcanDate.dateString(today)
        )

        let allGrades = try await gradesTask
        let allExams = try await examsTask
        let allHomework = try await homeworkTask

        let recentGrades = allGrades
            .filter { grade in
                guard let created = grade.createdAt, let date = VulcanDate.dateTime(created) else { return false }
                return date >= VulcanDate.addDays(today, -14)
            }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .prefix(5)

        let upcomingExams = allExams
            .filter { $0.deadlineAt >= VulcanDate.dateString(today) }
            .sorted { $0.deadlineAt < $1.deadlineAt }
            .prefix(4)

        let upcomingHomework = allHomework
            .filter { $0.deadlineAt >= VulcanDate.dateString(today) }
            .sorted { $0.deadlineAt < $1.deadlineAt }
            .prefix(4)

        return StartSnapshot(
            firstName: account.pupil.firstName,
            lucky: lucky?.number,
            grades: Array(recentGrades),
            exams: Array(upcomingExams),
            homework: Array(upcomingHomework)
        )
    }

    func loadGrades(period: Period) async throws -> GradesSnapshot {
        let (_, account, client, _) = try context()
        async let gradesTask = client.grades(
            unitId: account.unit.id,
            pupilId: account.pupil.id,
            periodId: period.id
        )
        async let averagesTask = client.averages(
            unitId: account.unit.id,
            pupilId: account.pupil.id,
            periodId: period.id
        )
        return GradesSnapshot(grades: try await gradesTask, averages: try await averagesTask)
    }

    func loadTimetable(weekStart: Date) async throws -> [Schedule] {
        let (_, account, client, _) = try context()
        return try await client.schedule(
            pupilId: account.pupil.id,
            from: VulcanDate.dateString(weekStart),
            to: VulcanDate.dateString(VulcanDate.addDays(weekStart, 6))
        )
    }

    func loadExams(weekStart: Date) async throws -> [Exam] {
        let (_, account, client, _) = try context()
        return try await client.exams(
            pupilId: account.pupil.id,
            from: VulcanDate.dateString(weekStart),
            to: VulcanDate.dateString(VulcanDate.addDays(weekStart, 6))
        )
    }

    func loadHomework(weekStart: Date) async throws -> [Homework] {
        let (_, account, client, _) = try context()
        return try await client.homework(
            pupilId: account.pupil.id,
            from: VulcanDate.dateString(weekStart),
            to: VulcanDate.dateString(VulcanDate.addDays(weekStart, 6))
        )
    }

    func loadNotes() async throws -> [Note] {
        let (_, account, client, _) = try context()
        return try await client.notes(pupilId: account.pupil.id)
    }

    func loadAnnouncements() async throws -> [Announcement] {
        let (_, account, client, _) = try context()
        return try await client.announcements(
            unitId: account.unit.id,
            pupilId: account.pupil.id
        )
    }

    var canSendMessages: Bool {
        guard let student = activeStudent else { return false }
        guard !student.account.unit.restURL.localizedCaseInsensitiveContains("hebe") else {
            return false
        }
        return student.login?.isEmpty == false
            && student.password?.isEmpty == false
            && student.tenant?.isEmpty == false
    }

    private func currentMailService() throws -> any MailService {
        guard let student = activeStudent else {
            throw VulcanError.noStudent
        }
        if let cachedMailService, cachedMailService.studentID == student.id {
            return cachedMailService.service
        }

        let service: any MailService
        if student.account.unit.restURL.localizedCaseInsensitiveContains("hebe") {
            guard let box = student.account.messageBox?.globalKey else {
                throw VulcanError.message("To konto nie ma skrzynki wiadomości.")
            }
            service = HebeMailService(
                client: HebeClient(student: student, session: session),
                box: box,
                pupilID: student.account.pupil.id,
                displayName: student.account.displayName
            )
        } else {
            guard let login = student.login, !login.isEmpty,
                  let password = student.password, !password.isEmpty,
                  let tenant = student.tenant, !tenant.isEmpty else {
                throw VulcanError.message("Zaloguj się ponownie, aby otworzyć wiadomości.")
            }
            service = PrometheusMailClient(
                student: student,
                session: session,
                initialCookies: mailCookies[student.id] ?? []
            )
        }

        cachedMailService = (studentID: student.id, service: service)
        return service
    }

    func loadMessages(kind: MessageKind) async throws -> [MailMessage] {
        let service = try currentMailService()
        do {
            return try await service.messages(kind: kind)
        } catch {
            invalidateMailSession(for: error)
            throw error
        }
    }

    func loadMessageDetail(id: String) async throws -> MailMessageDetail {
        let service = try currentMailService()
        do {
            return try await service.detail(id: id)
        } catch {
            invalidateMailSession(for: error)
            throw error
        }
    }

    func loadMailboxes() async throws -> [Mailbox] {
        let service = try currentMailService()
        do {
            return try await service.mailboxes()
        } catch {
            invalidateMailSession(for: error)
            throw error
        }
    }

    func markRead(id: String) async {
        do {
            try await currentMailService().markRead(id: id)
        } catch {
            // Messages are readable offline; a failed read receipt is not fatal.
            // Only discard the session when it has actually expired.
            invalidateMailSession(for: error)
        }
    }

    func sendMessage(
        _ draft: MailDraft,
        mode: MailSendMode,
        originalID: String?
    ) async throws {
        let service = try currentMailService()
        do {
            switch mode {
            case .new:
                try await service.send(draft)
            case .reply:
                guard let originalID else {
                    throw VulcanError.message("Brak wiadomości, na którą chcesz odpowiedzieć.")
                }
                try await service.reply(draft, to: originalID)
            case .forward:
                guard let originalID else {
                    throw VulcanError.message("Brak wiadomości do przekazania.")
                }
                try await service.forward(draft, from: originalID)
            }
        } catch {
            invalidateMailSession(for: error)
            throw error
        }
    }

    /// Clears the cached mailbox session. Transient failures (network, a
    /// rejected send, a failed read receipt) must not throw away cookies for
    /// every account and force another full portal login.
    private func invalidateMailSession(for error: Error) {
        guard let mailError = error as? PrometheusMailError else { return }
        switch mailError {
        case .sessionExpired, .loginFailed:
            invalidateMailSession()
        case .missingCredentials, .noMailbox, .invalidResponse, .server:
            break
        }
    }

    private func invalidateMailSession() {
        cachedMailService = nil
        mailCookies = [:]
    }

    // MARK: Diagnostics

    func refreshMailTrace() async {
        mailTrace = await MailTraceStore.shared.snapshot()
    }

    func clearMailTrace() async {
        await MailTraceStore.shared.clear()
        mailTrace = []
    }

    // MARK: Update check

    func checkForUpdate() async {
        updateInfo = nil
        guard let url = URL(string: "https://api.github.com/repos/Iwo24pl/EduExpose/releases") else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("EduExpose-iOS", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let latest = releases.first else {
                errorMessage = "Brak opublikowanych wydań."
                return
            }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            updateInfo = UpdateInfo(
                version: latest.tagName,
                url: URL(string: latest.htmlURL) ?? url,
                isNewer: latest.tagName != current
            )
        } catch {
            errorMessage = "Nie udało się sprawdzić aktualizacji."
        }
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Brak połączenia z internetem."
            case .timedOut:
                return "Serwer nie odpowiedział na czas."
            default:
                return "Błąd sieci: \(urlError.localizedDescription)"
            }
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.iwo24pl.eduexpose"
    private static let account = "students"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ data: Data) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VulcanError.message("Keychain: \(status)")
        }
    }

    static func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw VulcanError.message("Keychain: \(status)")
        }
        return data
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
