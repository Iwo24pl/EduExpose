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

/// One entry of the mailbox address book (`Pracownicy`, `Opiekunowie`,
/// `Uczniowie`). The server name keeps its `Imię Nazwisko - R - (Szkoła)`
/// shape, so the display fields reuse `VulcanMailboxName`.
struct MailContact: Identifiable, Hashable, Sendable {
    let globalKey: String
    let name: String
    let role: MailContactRole
    let displayName: String
    let school: String?

    init(globalKey: String, name: String, role: MailContactRole) {
        self.globalKey = globalKey
        self.name = name
        self.role = role
        let parsed = VulcanMailboxName.parse(name)
        displayName = parsed?.studentName ?? parsed?.name ?? name
        school = parsed?.shortSchoolName.nilIfEmpty
    }

    /// Role is part of the identity: the same person can be both a teacher and
    /// a parent, and the address book lists them with different mailbox keys.
    var id: String { "\(role.rawValue)-\(globalKey)" }

    var detail: String? { school }
}

enum MailContactRole: String, CaseIterable, Identifiable, Sendable {
    case employee
    case guardian
    case student

    var id: String { rawValue }

    var groupTitle: String {
        switch self {
        case .employee: return "Nauczyciele"
        case .guardian: return "Rodzice"
        case .student: return "Uczniowie"
        }
    }

    /// Role letter used by the server mailbox names: `P`, `R`/`O`, `U`.
    static func role(inName name: String) -> MailContactRole? {
        guard let role = VulcanMailboxName.parse(name)?.role else { return nil }
        switch role {
        case "P": return .employee
        case "R", "O": return .guardian
        case "U": return .student
        default: return nil
        }
    }
}

struct MailDraft: Sendable {
    var recipients: [MailContact]
    var subject: String
    var body: String
    /// Chosen "Od:" mailbox. `nil` keeps the mailbox the client resolves for
    /// the active pupil.
    var sender: Mailbox? = nil
}

/// The exact participants of a reply, when the server can provide their
/// mailbox keys. Names alone cannot be turned into recipients.
struct MailReplyRecipients: Sendable {
    var sender: MailContact?
    var recipients: [MailContact]

    static let none = MailReplyRecipients(sender: nil, recipients: [])
}

enum MailSendMode: Sendable, Equatable {
    case new
    case reply
    case forward
}

/// What the active mailbox implementation can actually do.
///
/// The screens use this to hide compose/delete actions instead of showing
/// buttons that can only fail. Read-only is the safe default.
struct MailCapabilities: Sendable, Equatable {
    var canCompose: Bool
    var canReply: Bool
    var canForward: Bool
    var canDelete: Bool

    static let readOnly = MailCapabilities(
        canCompose: false,
        canReply: false,
        canForward: false,
        canDelete: false
    )

    static let full = MailCapabilities(
        canCompose: true,
        canReply: true,
        canForward: true,
        canDelete: true
    )
}

// MARK: - Mail service boundary

protocol MailService: Sendable {
    var capabilities: MailCapabilities { get }
    func messages(kind: MessageKind) async throws -> [MailMessage]
    func detail(id: String) async throws -> MailMessageDetail
    func markRead(id: String) async throws
    func mailboxes() async throws -> [Mailbox]
    func contacts(sender: Mailbox?) async throws -> [MailContact]
    func send(_ draft: MailDraft) async throws
    func reply(_ draft: MailDraft, to id: String) async throws
    func forward(_ draft: MailDraft, from id: String) async throws
    func replyRecipients(for id: String) async throws -> MailReplyRecipients
    func delete(id: String, permanently: Bool) async throws
}

extension MailService {
    /// Existing Hebe accounts are read-only; Prometheus overrides this and
    /// Librus will provide its own capabilities.
    var capabilities: MailCapabilities { .readOnly }
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

        guard let name = group(1)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
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
        return Self.containsWord(first, in: haystack)
            && Self.containsWord(last, in: haystack)
    }

    /// Checks a whole word so `Jan` does not match `Janina`.
    static func containsWord(_ word: String, in text: String) -> Bool {
        let needle = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains {
                String($0).compare(
                    needle,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
    }

    /// The mailbox that belongs to a pupil. Shared by the client (sending) and
    /// the compose screen (default "Od:") so both pick the same one.
    static func bestMatch(
        in boxes: [Mailbox],
        firstName: String,
        surname: String
    ) -> Mailbox? {
        boxes.first { box in
            VulcanMailboxName.parse(box.name)?
                .matches(firstName: firstName, surname: surname) == true
        } ?? boxes.first { box in
            containsWord(firstName, in: box.name) && containsWord(surname, in: box.name)
        } ?? boxes.first
    }
}

// MARK: - Cookie hand-off

/// A Sendable snapshot of an `HTTPCookie`. Domain and path are preserved so the
/// cookie behaves like it did in the browser session that created it; cookies
/// are not copied onto unrelated hosts.
struct CookieSnapshot: Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let isSecure: Bool

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path.isEmpty ? "/" : cookie.path
        expires = cookie.expiresDate
        isSecure = cookie.isSecure
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expires {
            properties[.expires] = expires
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }

    /// Only the portal's own session cookies. Subdomain cookies from an old
    /// SSO/mailbox session must not be replayed into a new one, and unrelated
    /// VULCAN sessions (for example a Hebe registration cookie) are excluded.
    static func capturePortal(_ cookies: [HTTPCookie]) -> [CookieSnapshot] {
        cookies.filter { cookie in
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "eduvulcan.pl"
        }
        .map(CookieSnapshot.init)
    }
}

// MARK: - Helpers

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
