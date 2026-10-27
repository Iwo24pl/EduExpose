import Foundation

/// Typed endpoint access. All requests go through `LibrusSessionActor`,
/// which owns the cookies, refresh and relogin policy.
struct LibrusAPIClient: Sendable {
    let session: LibrusSessionActor
    let trace: LibrusTrace

    // MARK: Gateway endpoints

    func me() async throws -> LibrusMeEnvelope {
        try await get("Me")
    }

    func schools() async throws -> LibrusSchoolEnvelope {
        try await get("Schools")
    }

    func classes() async throws -> LibrusClassesEnvelope {
        try await get("Classes")
    }

    func userProfile() async throws -> LibrusUserProfileEnvelope {
        try await get("UserProfile")
    }

    func user(id: LibrusID) async throws -> LibrusUserEnvelope {
        try await get("Users/\(Self.path(id.raw))")
    }

    func subjects() async throws -> LibrusSubjectsEnvelope {
        try await get("Subjects")
    }

    func users() async throws -> LibrusUsersEnvelope {
        try await get("Users")
    }

    func classrooms() async throws -> LibrusClassroomsEnvelope {
        try await get("Classrooms")
    }

    func grades() async throws -> LibrusGradesEnvelope {
        try await get("Grades")
    }

    func gradeCategories() async throws -> LibrusGradeCategoriesEnvelope {
        try await get("Grades/Categories")
    }

    func gradeComments() async throws -> LibrusCommentsEnvelope {
        try await get("Grades/Comments")
    }

    func averages() async throws -> LibrusAveragesEnvelope {
        try await get("Grades/Averages")
    }

    func timetable(weekStart: String) async throws -> LibrusTimetableEnvelope {
        try await get("Timetables", query: [URLQueryItem(name: "weekStart", value: weekStart)])
    }

    func homeWorks() async throws -> LibrusHomeWorksEnvelope {
        try await get("HomeWorks")
    }

    func homeworkCategories() async throws -> LibrusHomeWorksCategoriesEnvelope {
        try await get("HomeWorks/Categories")
    }

    func homeworkAssignments() async throws -> LibrusHomeworkAssignmentsEnvelope {
        try await get("HomeWorkAssignments")
    }

    func notes() async throws -> LibrusNotesEnvelope {
        try await get("Notes")
    }

    func noteCategories() async throws -> LibrusNotesCategoriesEnvelope {
        try await get("Notes/Categories")
    }

    func schoolNotices() async throws -> LibrusSchoolNoticesEnvelope {
        try await get("SchoolNotices")
    }

    func luckyNumbers() async throws -> LibrusLuckyNumbersEnvelope {
        try await get("LuckyNumbers")
    }

    // MARK: Messages

    /// The Wiadomości subsystem has its own session. This bootstrap call
    /// sets the `wiadomosci.librus.pl` cookies; false means the school has
    /// no messages module, which is a normal answer.
    func bootstrapMessages() async throws -> Bool {
        do {
            let response = try await session.send(
                LibrusRequest(
                    url: LibrusConstants.messagesBootstrapURL,
                    followsRedirects: true
                )
            )
            if response.status == 403 || response.status == 404 {
                return false
            }
            guard (200..<300).contains(response.status) else {
                throw LibrusError.httpStatus(response.status)
            }
            if response.text.lowercased().contains("brak dostępu") {
                return false
            }
            return true
        } catch LibrusError.moduleUnavailable(_, 403) {
            return false
        } catch LibrusError.httpStatus(404) {
            return false
        }
    }

    func messages(mailbox: String, limit: Int = 50, page: Int = 1) async throws -> LibrusMessageListEnvelope {
        try await get(
            "\(Self.path(mailbox))/messages",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "page", value: String(page))
            ],
            base: LibrusConstants.messagesBase
        )
    }

    func message(mailbox: String, id: String) async throws -> LibrusMessageEnvelope {
        try await get(
            "\(Self.path(mailbox))/messages/\(Self.path(id))",
            base: LibrusConstants.messagesBase
        )
    }

    func unreadMessagesCount() async throws -> LibrusUnreadEnvelope {
        try await get("inbox/unreadMessagesCount", base: LibrusConstants.messagesBase)
    }

    // MARK: Transport

    private func get<T: Decodable>(
        _ endpoint: String,
        query: [URLQueryItem] = [],
        base: URL = LibrusConstants.gatewayBase
    ) async throws -> T {
        let data = try await getData(endpoint, query: query, base: base)
        do {
            return try JSONDecoder.vulcan().decode(T.self, from: data)
        } catch {
            throw LibrusError.decoding(endpoint: endpoint)
        }
    }

    private func getData(
        _ endpoint: String,
        query: [URLQueryItem] = [],
        base: URL = LibrusConstants.gatewayBase
    ) async throws -> Data {
        guard let url = Self.url(base: base, endpoint: endpoint, query: query) else {
            throw LibrusError.unsafeURL
        }
        let response = try await session.send(LibrusRequest(
            url: url,
            headers: [
                "Accept": "application/json, text/plain, */*",
                "X-Requested-With": "XMLHttpRequest"
            ]
        ))
        guard !response.body.isEmpty else {
            throw LibrusError.unexpectedResponse
        }
        return response.body
    }

    private static func url(base: URL, endpoint: String, query: [URLQueryItem]) -> URL? {
        var text = base.absoluteString
        if !text.hasSuffix("/") {
            text += "/"
        }
        let path = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        text += path
        guard var components = URLComponents(string: text) else { return nil }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    private static func path(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/"
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
