import Foundation

// MARK: - Source-neutral mail models

struct Mailbox: Identifiable, Hashable, Sendable {
    let globalKey: String
    let name: String
    let type: Int?

    var id: String { globalKey }

    var displayName: String {
        guard let parsed = VulcanMailboxName.parse(name) else { return name }
        return parsed.studentName ?? parsed.name
    }

    var detail: String? {
        guard let parsed = VulcanMailboxName.parse(name),
              parsed.studentName != nil,
              !parsed.shortSchoolName.isEmpty else {
            return nil
        }
        return parsed.shortSchoolName
    }
}

struct MailAttachment: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL?
}

struct MailMessage: Identifiable, Hashable, Sendable {
    let id: String
    let subject: String
    let correspondent: String
    let date: String
    let isUnread: Bool
    let hasAttachments: Bool
    /// Hebe returns the body with the list; Prometheus fetches it separately.
    let inlineBody: String?
    let inlineAttachments: [MailAttachment]
}

struct MailMessageDetail: Sendable {
    let id: String
    let subject: String
    let sender: String
    let recipients: [String]
    let date: String
    let body: String
    let attachments: [MailAttachment]
}

struct MailDraft: Sendable {
    var recipients: [Mailbox]
    var subject: String
    var body: String
}

enum MailSendMode: Sendable, Equatable {
    case new
    case reply
    case forward
}

// MARK: - Mail service boundary

protocol MailService: Sendable {
    func messages(kind: MessageKind) async throws -> [MailMessage]
    func detail(id: String) async throws -> MailMessageDetail
    func markRead(id: String) async throws
    func mailboxes() async throws -> [Mailbox]
    func send(_ draft: MailDraft) async throws
    func reply(_ draft: MailDraft, to id: String) async throws
    func forward(_ draft: MailDraft, from id: String) async throws
}

// MARK: - Prometheus mailbox name

/// Parses names such as `Jan Kowalski [jan] - O - (Szkoła)`.
/// The web mailbox can use different role letters; the fields we depend on
/// are the display name, the optional student name and the school name.
struct VulcanMailboxName: Equatable, Sendable {
    let name: String
    let code: String?
    let studentName: String?
    let role: String
    let shortSchoolName: String

    static func parse(_ input: String) -> VulcanMailboxName? {
        let pattern = #"\s*(.*?)\s*(?:\[([^\]]+)\])?\s*-\s*([OPRU])\s*-\s*(.+\s*-\s*)?\((.+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: input,
                range: NSRange(input.startIndex..., in: input)
              ) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges,
                  match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: input) else {
                return nil
            }
            return String(input[range])
        }

        guard let name = group(1)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let code = group(2)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        var studentName = group(4)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if studentName?.hasSuffix("-") == true {
            studentName?.removeLast()
        }
        studentName = studentName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return VulcanMailboxName(
            name: name,
            code: code,
            studentName: studentName,
            role: group(3) ?? "",
            shortSchoolName: group(5)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    func matches(firstName: String, surname: String) -> Bool {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = surname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !last.isEmpty else { return false }
        let haystack = studentName ?? name
        return haystack.range(of: first, options: .caseInsensitive) != nil
            && haystack.range(of: last, options: .caseInsensitive) != nil
    }
}

// MARK: - Cookie hand-off

/// A Sendable snapshot of an `HTTPCookie`. The client recreates the cookie for
/// each VULCAN host instead of relying on the shared login cookie domain.
struct CookieSnapshot: Sendable {
    let name: String
    let value: String
    let expires: Date?
    let isSecure: Bool

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        expires = cookie.expiresDate
        isSecure = cookie.isSecure
    }

    func cookie(for domain: String) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/"
        ]
        if let expires {
            properties[.expires] = expires
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }

    static func capture(_ cookies: [HTTPCookie]) -> [CookieSnapshot] {
        cookies.map { CookieSnapshot(cookie: $0) }
    }
}

// MARK: - Helpers

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
