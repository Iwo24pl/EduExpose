import Foundation

/// Read-only message adapter for units whose `restUrl` is the Hebe archive.
/// New accounts use `PrometheusMailClient`; composing stays unavailable here.
actor HebeMailService: MailService {
    private let client: HebeClient
    private let box: String
    private let pupilID: Int
    private let mailbox: Mailbox
    private var cache: [String: Message] = [:]

    init(client: HebeClient, box: String, pupilID: Int, displayName: String) {
        self.client = client
        self.box = box
        self.pupilID = pupilID
        mailbox = Mailbox(globalKey: box, name: displayName, type: nil)
    }

    func messages(kind: MessageKind) async throws -> [MailMessage] {
        let messages = try await client.messages(box: box, pupilId: pupilID, kind: kind)
        for message in messages {
            cache[message.globalKey] = message
        }
        return messages.map { message in
            MailMessage(
                id: message.globalKey,
                subject: message.subject,
                correspondent: correspondent(for: message, kind: kind),
                date: message.sentAt,
                isUnread: kind == .received && message.status == 0,
                hasAttachments: message.attachments?.isEmpty == false,
                inlineBody: message.content,
                inlineAttachments: attachments(for: message)
            )
        }
    }

    func detail(id: String) async throws -> MailMessageDetail {
        let message = try await findMessage(id: id)
        return MailMessageDetail(
            id: message.globalKey,
            subject: message.subject,
            sender: message.sender.name,
            recipients: (message.receiver ?? []).map(\.name),
            date: message.sentAt,
            body: message.content,
            attachments: attachments(for: message)
        )
    }

    func markRead(id: String) async throws {
        try await client.markRead(
            box: box,
            messageKey: id,
            pupilId: pupilID
        )
    }

    func mailboxes() async throws -> [Mailbox] {
        [mailbox]
    }

    /// Hebe accounts are read-only in this app, so compose never asks for an
    /// address book.
    func contacts(sender: Mailbox?) async throws -> [MailContact] {
        []
    }

    func send(_ draft: MailDraft) async throws {
        throw VulcanError.message("Wysyłanie wiadomości jest dostępne tylko dla skrzynki Prometheus.")
    }

    func reply(_ draft: MailDraft, to id: String) async throws {
        throw VulcanError.message("Odpowiadanie jest dostępne tylko dla skrzynki Prometheus.")
    }

    func forward(_ draft: MailDraft, from id: String) async throws {
        throw VulcanError.message("Przekazywanie jest dostępne tylko dla skrzynki Prometheus.")
    }

    func replyRecipients(for id: String) async throws -> MailReplyRecipients {
        .none
    }

    func delete(id: String, permanently: Bool) async throws {
        throw VulcanError.message("Usuwanie wiadomości jest dostępne tylko dla skrzynki Prometheus.")
    }

    private func findMessage(id: String) async throws -> Message {
        if let cached = cache[id] {
            return cached
        }
        // A message only lives in one mailbox, so a failure in another one
        // must not hide a match we could still find.
        var lastError: Error?
        for kind in MessageKind.allCases {
            do {
                let messages = try await client.messages(box: box, pupilId: pupilID, kind: kind)
                for message in messages {
                    cache[message.globalKey] = message
                }
            } catch {
                lastError = error
            }
        }
        if let message = cache[id] {
            return message
        }
        if let lastError {
            throw lastError
        }
        throw VulcanError.message("Nie znaleziono wiadomości.")
    }

    private func correspondent(for message: Message, kind: MessageKind) -> String {
        switch kind {
        case .received:
            return message.sender.name
        case .sent, .deleted:
            let names = (message.receiver ?? []).map(\.name)
            return names.isEmpty ? message.sender.name : names.joined(separator: ", ")
        }
    }

    private func attachments(for message: Message) -> [MailAttachment] {
        (message.attachments ?? []).enumerated().map { index, attachment in
            MailAttachment(
                id: "\(message.globalKey)-\(index)",
                name: attachment.name,
                url: Self.webURL(attachment.link)
            )
        }
    }

    /// Relative or non-web links cannot be opened from the attachment row.
    private static func webURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}
