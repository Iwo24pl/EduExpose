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
    var students: [RegistryStudent] = []
    var activeID: String?
    var pending: [RegistryStudent] = []
    var selected: Set<String> = []
    var isBusy = false
    var isAddingAccount = false
    var errorMessage: String?
    var updateInfo: UpdateInfo?
    var mailTrace: [MailTraceEvent] = []
    var librusTrace: [LibrusTraceEvent] = []

    let session: URLSession

    @ObservationIgnored private var journals: [String: any JournalService] = [:]
    @ObservationIgnored private var hebeClients: [String: HebeClient] = [:]
    @ObservationIgnored private var librusActors: [String: LibrusSessionActor] = [:]
    @ObservationIgnored private var cachedMailService: (studentID: String, service: any MailService)?
    @ObservationIgnored private var mailCookies: [String: [CookieSnapshot]] = [:]
    @ObservationIgnored private let librusAuth = LibrusAuthService()
    @ObservationIgnored private let librusTraceStore = LibrusTrace()

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

    var activeStudent: RegistryStudent? {
        students.first { $0.id == activeID }
    }

    var activeAccount: Account? {
        activeStudent?.account
    }

    var activeProvider: EduRegistry? {
        activeStudent?.provider
    }

    // MARK: Session lifecycle

    func bootstrap() async {
        guard phase == .launching else { return }
        if let data = try? KeychainStore.load() {
            if let stored = try? JSONDecoder().decode([RegistryStudent].self, from: data) {
                students = stored
            } else if let legacy = try? JSONDecoder().decode([StoredStudent].self, from: data) {
                // EduExpose 1.x stored a flat eduVULCAN array. Keep the same
                // Keychain account so an upgrade never loses the session.
                students = legacy.map { RegistryStudent(legacy: $0) }
                save()
            }
        }

        for student in students {
            await install(student)
        }
        activeID = students.first(where: { $0.isEnabled })?.id ?? students.first?.id
        phase = students.isEmpty ? .login : .dashboard
    }

    func login(provider: EduRegistry, login rawLogin: String, password: String) async {
        let login = rawLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty, !password.isEmpty else {
            errorMessage = provider == .librus
                ? "Podaj e-mail i hasło do Konto LIBRUS."
                : "Podaj login i hasło."
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            let found: [RegistryStudent]
            switch provider {
            case .eduVulcan:
                found = try await PrometheusAuthService(session: session)
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
            case .librus:
                found = try await librusAuth.signIn(login: login, password: password)
                mailCookies = [:]
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

    func confirmSelection() async {
        let chosen = pending.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else {
            errorMessage = "Wybierz co najmniej jednego ucznia."
            return
        }

        var merged = students
        var installed = 0
        var firstError: String?
        for student in chosen {
            do {
                try await prepare(student)
                if let index = merged.firstIndex(where: { $0.id == student.id }) {
                    merged[index] = student
                } else {
                    merged.append(student)
                }
                installed += 1
            } catch {
                if firstError == nil {
                    firstError = Self.describe(error)
                }
            }
        }

        guard installed > 0 else {
            errorMessage = firstError ?? "Nie udało się dodać konta."
            return
        }

        cachedMailService = nil
        students = merged.sorted { $0.account.displayName < $1.account.displayName }
        activeID = chosen.first?.id ?? activeID
        pending = []
        selected = []
        isAddingAccount = false
        errorMessage = firstError
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
        journals[id] = nil
        hebeClients[id] = nil
        librusActors[id] = nil
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
        journals = [:]
        hebeClients = [:]
        librusActors = [:]
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

    /// Builds the live provider objects for one stored student. Called after
    /// bootstrap, after account selection, and when the active session is
    /// replaced.
    private func prepare(_ student: RegistryStudent) async throws {
        switch student.provider {
        case .eduVulcan:
            guard let legacy = student.legacyStoredStudent else {
                throw VulcanError.message("Brak sesji eduVULCAN.")
            }
            let client = HebeClient(student: legacy, session: session)
            hebeClients[student.id] = client
            journals[student.id] = HebeJournalService(
                client: client,
                account: student.account
            )

        case .librus:
            let observer = librusObserver(for: student.id)
            let actor = try await librusAuth.makeSession(
                for: student,
                onSessionUpdate: observer
            )
            librusActors[student.id] = actor
            journals[student.id] = LibrusJournalService(
                session: actor,
                trace: librusTraceStore
            )
        }
    }

    private func install(_ student: RegistryStudent) async {
        do {
            try await prepare(student)
        } catch {
            await traceLibrus("prepare.fail", note: student.provider.rawValue)
        }
    }

    private func librusObserver(for id: String) -> LibrusSessionObserver {
        { [weak self] session in
            await self?.updateLibrusSession(session, for: id)
        }
    }

    private func updateLibrusSession(_ session: LibrusSession, for id: String) {
        guard let index = students.firstIndex(where: { $0.id == id }) else { return }
        students[index].session = .librus(session)
        save()
    }

    private func save() {
        do {
            try KeychainStore.save(JSONEncoder().encode(students))
        } catch {
            errorMessage = "Nie udało się zapisać sesji w Keychain."
        }
    }

    // MARK: Loading

    private struct Context {
        let student: RegistryStudent
        let account: Account
        let journal: any JournalService
        let period: Period
    }

    private func context() throws -> Context {
        guard let id = activeID,
              let student = students.first(where: { $0.id == id }) else {
            throw VulcanError.noStudent
        }
        guard let journal = journals[id] else {
            throw VulcanError.noStudent
        }
        guard let period = student.account.currentPeriod else {
            throw VulcanError.noPeriod
        }
        return Context(
            student: student,
            account: student.account,
            journal: journal,
            period: period
        )
    }

    func loadStart() async throws -> StartSnapshot {
        let context = try context()
        let today = Date()

        async let gradesTask = context.journal.grades(period: context.period)
        async let examsTask = context.journal.exams(from: today, to: VulcanDate.addDays(today, 14))
        async let homeworkTask = context.journal.homework(from: today, to: VulcanDate.addDays(today, 14))
        let lucky = try? await context.journal.luckyNumber(day: today)
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
            firstName: context.account.pupil.firstName,
            lucky: lucky,
            grades: Array(recentGrades),
            exams: Array(upcomingExams),
            homework: Array(upcomingHomework)
        )
    }

    func loadGrades(period: Period) async throws -> GradesSnapshot {
        let context = try context()
        async let gradesTask = context.journal.grades(period: period)
        async let averagesTask = context.journal.averages(period: period)
        return GradesSnapshot(grades: try await gradesTask, averages: try await averagesTask)
    }

    func loadAttendance(period: Period) async throws -> AttendanceSnapshot {
        let context = try context()
        return try await context.journal.attendance(period: period)
    }

    func loadTimetable(weekStart: Date) async throws -> [Schedule] {
        let context = try context()
        return try await context.journal.timetable(
            from: weekStart,
            to: VulcanDate.addDays(weekStart, 6)
        )
    }

    func loadExams(weekStart: Date) async throws -> [Exam] {
        let context = try context()
        return try await context.journal.exams(
            from: weekStart,
            to: VulcanDate.addDays(weekStart, 6)
        )
    }

    func loadHomework(weekStart: Date) async throws -> [Homework] {
        let context = try context()
        return try await context.journal.homework(
            from: weekStart,
            to: VulcanDate.addDays(weekStart, 6)
        )
    }

    func loadNotes() async throws -> [Note] {
        try await context().journal.notes()
    }

    func loadAnnouncements() async throws -> [Announcement] {
        try await context().journal.announcements()
    }

    // MARK: Messages

    var mailCapabilities: MailCapabilities {
        guard let student = activeStudent else { return .readOnly }
        return Self.capabilities(for: student)
    }

    var canSendMessages: Bool {
        mailCapabilities.canCompose
    }

    private static func capabilities(for student: RegistryStudent) -> MailCapabilities {
        switch student.provider {
        case .librus:
            return .readOnly
        case .eduVulcan:
            let isHebe = student.account.unit.restURL.localizedCaseInsensitiveContains("hebe")
            guard !isHebe,
                  let session = student.eduVulcanSession,
                  session.login?.isEmpty == false,
                  session.password?.isEmpty == false,
                  session.tenant?.isEmpty == false else {
                return .readOnly
            }
            return .full
        }
    }

    private func currentMailService() throws -> any MailService {
        guard let student = activeStudent else {
            throw VulcanError.noStudent
        }
        if let cachedMailService, cachedMailService.studentID == student.id {
            return cachedMailService.service
        }

        let service: any MailService
        switch student.provider {
        case .librus:
            guard let actor = librusActors[student.id] else {
                throw LibrusError.missingSession
            }
            service = LibrusMailService(
                session: actor,
                displayName: student.account.displayName,
                trace: librusTraceStore
            )

        case .eduVulcan:
            guard let legacy = student.legacyStoredStudent else {
                throw VulcanError.message("Zaloguj się ponownie, aby otworzyć wiadomości.")
            }
            if student.account.unit.restURL.localizedCaseInsensitiveContains("hebe") {
                guard let box = student.account.messageBox?.globalKey else {
                    throw VulcanError.message("To konto nie ma skrzynki wiadomości.")
                }
                let client = hebeClients[student.id]
                    ?? HebeClient(student: legacy, session: session)
                service = HebeMailService(
                    client: client,
                    box: box,
                    pupilID: student.account.pupil.id,
                    displayName: student.account.displayName
                )
            } else {
                service = PrometheusMailClient(
                    student: legacy,
                    session: session,
                    initialCookies: mailCookies[student.id] ?? []
                )
            }
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

    /// The default "Od:" mailbox for the active pupil.
    func defaultSender(in boxes: [Mailbox]) -> Mailbox? {
        guard let pupil = activeAccount?.pupil else { return boxes.first }
        return VulcanMailboxName.bestMatch(
            in: boxes,
            firstName: pupil.firstName,
            surname: pupil.surname
        )
    }

    func loadContacts(sender: Mailbox?) async throws -> [MailContact] {
        let service = try currentMailService()
        do {
            return try await service.contacts(sender: sender)
        } catch {
            invalidateMailSession(for: error)
            throw error
        }
    }

    func replyRecipients(for id: String) async throws -> MailReplyRecipients {
        let service = try currentMailService()
        do {
            return try await service.replyRecipients(for: id)
        } catch {
            invalidateMailSession(for: error)
            throw error
        }
    }

    func deleteMessage(id: String, permanently: Bool) async throws {
        let service = try currentMailService()
        do {
            try await service.delete(id: id, permanently: permanently)
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
        if let mailError = error as? PrometheusMailError {
            switch mailError {
            case .sessionExpired, .loginFailed:
                invalidateMailSession()
            case .missingCredentials, .noMailbox, .invalidResponse, .server:
                break
            }
            return
        }
        if let librusError = error as? LibrusError {
            switch librusError {
            case .sessionExpired, .reauthRequired, .missingSession:
                invalidateMailSession()
            default:
                break
            }
        }
    }

    private func invalidateMailSession() {
        cachedMailService = nil
        mailCookies = [:]
    }

    // MARK: Diagnostics

    func refreshMailTrace() async {
        mailTrace = await MailTraceStore.shared.snapshot()
        librusTrace = await librusTraceStore.snapshot()
    }

    func clearMailTrace() async {
        await MailTraceStore.shared.clear()
        await librusTraceStore.clear()
        mailTrace = []
        librusTrace = []
    }

    private func traceLibrus(_ stage: String, note: String? = nil) async {
        await librusTraceStore.record(stage, note: note)
    }

    // MARK: Update check

    func checkForUpdate() async {
        updateInfo = nil
        guard let url = URL(
            string: "https://api.github.com/repos/Iwo24pl/EduExpose/releases?per_page=30"
        ) else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("EduExpose-iOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                errorMessage = "Nie udało się sprawdzić aktualizacji."
                return
            }

            let releases = try JSONDecoder().decode([AppRelease].self, from: data)
            let currentRaw = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "1.0.0"
            guard let current = AppVersion(currentRaw) else {
                errorMessage = "Nie udało się odczytać wersji aplikacji."
                return
            }
            guard let newest = AppReleasePicker.newest(in: releases, current: current) else {
                errorMessage = "Brak opublikowanych wydań."
                return
            }

            updateInfo = UpdateInfo(
                version: newest.release.tagName,
                url: URL(string: newest.release.htmlURL) ?? url,
                isNewer: current < newest.version
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
