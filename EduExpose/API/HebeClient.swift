import Foundation

/// Authenticated client for the VULCAN Hebe CE REST API.
actor HebeClient {
    private let session: URLSession
    private var credential: HebeCredential
    private var restUrl: String

    init(credential: HebeCredential, session: URLSession) {
        self.credential = credential
        self.session = session
        self.restUrl = credential.restUrl ?? ""
    }

    init(student: StoredStudent, session: URLSession) {
        self.credential = student.credential
        self.session = session
        self.restUrl = Self.dataEndpoint(for: student.account, fallback: student.restUrl)
    }

    /// Data endpoints live on the unit endpoint (`/<tenant>/<unit>/api`), not on
    /// the tenant endpoint used to list accounts. Calling the tenant endpoint
    /// without the unit symbol returns status 104 (`Brak symbolu jednostki`).
    static func dataEndpoint(for account: Account, fallback: String) -> String {
        let unit = account.unit.restURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? fallback : unit
    }

    // MARK: Registration

    func registerJWT(tokens: [String], tenant: String) async throws -> HebeCredential {
        let base = "https://lekcjaplus.vulcan.net.pl/\(tenant.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/api"
        let payload: [String: Any] = [
            "OS": "iOS",
            "Certificate": credential.certificate,
            "CertificateType": credential.type,
            "DeviceModel": credential.deviceModel,
            "SelfIdentifier": credential.deviceId,
            "CertificateThumbprint": credential.fingerprint,
            "Tokens": tokens
        ]
        _ = try await send(method: "POST", path: "mobile/register/jwt", base: base, payload: payload, pupilId: nil)
        restUrl = base
        credential.restUrl = base
        return credential
    }

    func accounts() async throws -> [Account] {
        try await fetch([Account].self, path: "mobile/register/hebe", query: ["mode": "2"])
    }

    // MARK: Grades

    func grades(unitId: Int, pupilId: Int, periodId: Int) async throws -> [Grade] {
        try await fetch([Grade].self, path: "mobile/grade/byPupil", query: [
            "unitId": String(unitId),
            "pupilId": String(pupilId),
            "periodId": String(periodId),
            "lastSyncDate": Self.epoch,
            "lastId": "-2147483648",
            "pageSize": "500"
        ], pupilId: pupilId)
    }

    func averages(unitId: Int, pupilId: Int, periodId: Int) async throws -> [GradeAverage] {
        try await fetch([GradeAverage].self, path: "mobile/grade/average/byPupil", query: [
            "unitId": String(unitId),
            "pupilId": String(pupilId),
            "periodId": String(periodId),
            "lastId": "-2147483648",
            "pageSize": "500",
            "scope": "auto"
        ], pupilId: pupilId)
    }

    // MARK: Exams and homework

    func exams(pupilId: Int, from: String, to: String) async throws -> [Exam] {
        try await fetch([Exam].self, path: "mobile/exam/byPupil", query: [
            "pupilId": String(pupilId),
            "dateFrom": from,
            "dateTo": to,
            "lastSyncDate": Self.epoch,
            "lastId": "-2147483648",
            "pageSize": "500"
        ], pupilId: pupilId)
    }

    func homework(pupilId: Int, from: String, to: String) async throws -> [Homework] {
        try await fetch([Homework].self, path: "mobile/homework/byPupil", query: [
            "pupilId": String(pupilId),
            "dateFrom": from,
            "dateTo": to,
            "lastSyncDate": Self.epoch,
            "lastId": "-2147483648",
            "pageSize": "500"
        ], pupilId: pupilId)
    }

    // MARK: Timetable

    func schedule(pupilId: Int, from: String, to: String) async throws -> [Schedule] {
        try await fetch([Schedule].self, path: "mobile/schedule/withchanges/byPupil", query: [
            "pupilId": String(pupilId),
            "dateFrom": from,
            "dateTo": to,
            "lastId": "-2147483648",
            "pageSize": "500",
            "lastSyncDate": Self.epoch
        ], pupilId: pupilId)
    }

    // MARK: Notes and announcements

    func notes(pupilId: Int) async throws -> [Note] {
        try await fetch([Note].self, path: "mobile/note/byPupil", query: [
            "pupilId": String(pupilId),
            "lastId": "-2147483648",
            "pageSize": "500",
            "lastSyncDate": Self.epoch
        ], pupilId: pupilId)
    }

    func announcements(unitId: Int, pupilId: Int) async throws -> [Announcement] {
        try await fetch([Announcement].self, path: "mobile/announcement/byPupil", query: [
            "unitId": String(unitId),
            "pupilId": String(pupilId),
            "view": "6",
            "lastId": "-2147483648",
            "pageSize": "500"
        ], pupilId: pupilId)
    }

    // MARK: Attendance

    func presenceMonthStats(pupilId: Int, periodId: Int) async throws -> [PresenceMonthStats] {
        try await fetch(
            [PresenceMonthStats].self,
            path: "mobile/presence/stats/perMonth",
            query: [
                "pupilId": String(pupilId),
                "periodId": String(periodId)
            ],
            pupilId: pupilId
        )
    }

    func presenceSubjectStats(pupilId: Int, periodId: Int) async throws -> [PresenceSubjectStats] {
        try await fetch(
            [PresenceSubjectStats].self,
            path: "mobile/presence/stats/perSubject",
            query: [
                "pupilId": String(pupilId),
                "periodId": String(periodId)
            ],
            pupilId: pupilId
        )
    }

    func presenceExtra(pupilId: Int, from: String, to: String) async throws -> [PresenceExtra] {
        try await fetch(
            [PresenceExtra].self,
            path: "mobile/presence/extra/byPupil",
            query: [
                "pupilId": String(pupilId),
                "dateFrom": from,
                "dateTo": to,
                "lastSyncDate": Self.epoch,
                "lastId": "-2147483648",
                "pageSize": "500"
            ],
            pupilId: pupilId
        )
    }

    func luckyNumber(pupilId: Int, constituentId: Int, day: String) async throws -> LuckyNumber? {
        let data = try await send(method: "GET", path: "mobile/school/lucky", query: [
            "pupilId": String(pupilId),
            "constituentId": String(constituentId),
            "day": day
        ], pupilId: pupilId)
        let box = try JSONDecoder.vulcan().decode(StatusBox.self, from: data)
        try Self.check(box.status)
        return try? JSONDecoder.vulcan().decode(EnvelopeBox<LuckyNumber>.self, from: data).envelope
    }

    // MARK: Messages

    func messages(box: String, pupilId: Int, kind: MessageKind) async throws -> [Message] {
        let path: String
        switch kind {
        case .received: path = "mobile/messages/received/byBox"
        case .sent: path = "mobile/messages/sent/byBox"
        case .deleted: path = "mobile/messages/deleted/byBox"
        }
        return try await fetch([Message].self, path: path, query: [
            "box": box,
            "pupilId": String(pupilId),
            "lastId": "-2147483648",
            "pageSize": "500",
            "lastSyncDate": Self.epoch
        ], pupilId: pupilId)
    }

    func markRead(box: String, messageKey: String, pupilId: Int) async throws {
        let data = try await send(method: "POST", path: "mobile/messages/status", payload: [
            "BoxKey": box,
            "MessageKey": messageKey,
            "Status": 1
        ], pupilId: pupilId)
        let box = try JSONDecoder.vulcan().decode(StatusBox.self, from: data)
        try Self.check(box.status)
    }

    // MARK: Transport

    private static let epoch = "1970-01-01 01:00:00"

    private struct StatusBox: Decodable {
        let status: ApiStatus
    }

    private func fetch<T: Decodable>(
        _ type: T.Type,
        path: String,
        query: [String: String] = [:],
        pupilId: Int? = nil
    ) async throws -> T {
        let data = try await send(method: "GET", path: path, query: query, pupilId: pupilId)
        let box = try JSONDecoder.vulcan().decode(EnvelopeBox<T>.self, from: data)
        try Self.check(box.status)
        guard let envelope = box.envelope else {
            throw VulcanError.invalidResponse
        }
        return envelope
    }

    private func send(
        method: String,
        path: String,
        base: String? = nil,
        query: [String: String] = [:],
        payload: [String: Any]? = nil,
        pupilId: Int?
    ) async throws -> Data {
        var root = (base ?? restUrl).trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard !root.isEmpty else {
            throw VulcanError.message("Urządzenie nie jest zarejestrowane.")
        }
        if !root.hasSuffix("/api") {
            root += "/api"
        }

        let signedURL = root + "/" + path
        var components = URLComponents(string: signedURL)
        if !query.isEmpty {
            components?.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw VulcanError.invalidResponse
        }

        let body: Data? = payload.flatMap { try? Self.bodyData($0) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("iOS", forHTTPHeaderField: "vOS")
        request.setValue("998", forHTTPHeaderField: "vVersionCode")
        request.setValue("1", forHTTPHeaderField: "vAPI")
        request.setValue("Dart/3.11 (dart:io)", forHTTPHeaderField: "User-Agent")
        if let pupilId {
            request.setValue(String(pupilId), forHTTPHeaderField: "vHint")
        }
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in try Signing.headers(credential: credential, body: body, url: signedURL) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VulcanError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let text = String(decoding: data, as: UTF8.self)
            throw VulcanError.message("Serwer zwrócił błąd \(http.statusCode). \(text.prefix(180))")
        }
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("!DOCTYPE") {
            throw VulcanError.invalidResponse
        }
        return data
    }

    private static func bodyData(_ payload: [String: Any]) throws -> Data {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let body: [String: Any] = [
            "AppName": "DzienniczekPlus 3.0",
            "AppVersion": "26.06.02",
            "NotificationToken": "",
            "API": 1,
            "RequestId": UUID().uuidString.lowercased(),
            "Timestamp": Int(now.timeIntervalSince1970),
            "TimestampFormatted": formatter.string(from: now),
            "Envelope": payload
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private static func check(_ status: ApiStatus) throws {
        switch status.code {
        case 0:
            return
        case -1:
            throw VulcanError.message(status.message.isEmpty ? "Błąd wewnętrzny serwera." : status.message)
        case 100, 102, 103:
            throw VulcanError.message("Nieprawidłowe podpisanie żądania. Spróbuj zalogować się ponownie.")
        case 104:
            throw VulcanError.message("Brak symbolu jednostki.")
        case 154:
            throw VulcanError.message("Urządzenie nie jest zarejestrowane. Zaloguj się ponownie.")
        case 200:
            throw VulcanError.message("Nie znaleziono danych.")
        case 201, 202, 204:
            throw VulcanError.message("Sesja wygasła. Zaloguj się ponownie.")
        case 203:
            throw VulcanError.message("Nieprawidłowy PIN.")
        case 206, 214:
            throw VulcanError.message(status.message.isEmpty ? "Nieprawidłowe dane żądania." : status.message)
        default:
            throw VulcanError.message(status.message.isEmpty ? "Błąd serwera (\(status.code))." : status.message)
        }
    }
}
