import Foundation

/// Read-only adaptation of the Librus Wiadomości API.
///
/// The messages session expires independently from the journal session, so
/// a rejected call first reboots `wiadomosci3` once and only then allows the
/// main session actor to refresh or log in.
actor LibrusMailService: MailService {
    nonisolated var capabilities: MailCapabilities { .readOnly }

    private let session: LibrusSessionActor
    private let client: LibrusAPIClient
    private let displayName: String

    private var messagesAvailable: Bool?
    private var deniedAt: Date?
    private var lastLoginCount: Int?

    init(
        session: LibrusSessionActor,
        displayName: String,
        trace: LibrusTrace = LibrusTrace()
    ) {
        self.session = session
        self.client = LibrusAPIClient(session: session, trace: trace)
        self.displayName = displayName
    }

    func messages(kind: MessageKind) async throws -> [MailMessage] {
        let mailbox = Self.mailbox(for: kind)
        let client = self.client
        do {
            let envelope = try await withMessages {
                try await client.messages(mailbox: mailbox, limit: 100, page: 1)
            }
            return (envelope.data ?? []).compactMap { summary in
                guard let id = summary.messageId?.raw, !id.isEmpty else { return nil }
                return MailMessage(
                    id: id,
                    subject: summary.topic ?? "(brak tematu)",
                    correspondent: correspondent(for: summary, kind: kind),
                    date: summary.sendDate ?? "",
                    isUnread: kind == .received
                        && (summary.readDate == nil || summary.readDate?.isEmpty == true),
                    hasAttachments: summary.isAnyFileAttached == true,
                    inlineBody: nil,
                    inlineAttachments: []
                )
            }
        } catch let error as LibrusError {
            if case .httpStatus(404) = error {
                return []
            }
            throw error
        }
    }

    func detail(id: String) async throws -> MailMessageDetail {
        let client = self.client
        return try await withMessages {
            var lastError: any Error = LibrusError.httpStatus(404)
            for mailbox in ["inbox", "outbox", "trash"] {
                do {
                    let envelope = try await client.message(mailbox: mailbox, id: id)
                    if let detail = envelope.data {
                        return self.detail(from: detail, fallbackID: id)
                    }
                } catch {
                    lastError = error
                    if let librusError = error as? LibrusError,
                       case .httpStatus(404) = librusError {
                        continue
                    }
                    throw error
                }
            }
            throw lastError
        }
    }

    func markRead(id: String) async throws {
        // Opening a Librus message marks it read on the server. The list
        // cache is intentionally not shared, so there is nothing to do.
    }

    func mailboxes() async throws -> [Mailbox] {
        [Mailbox(globalKey: "inbox", name: displayName, type: nil)]
    }

    func contacts(sender: Mailbox?) async throws -> [MailContact] {
        []
    }

    func send(_ draft: MailDraft) async throws {
        throw LibrusError.readOnly
    }

    func reply(_ draft: MailDraft, to id: String) async throws {
        throw LibrusError.readOnly
    }

    func forward(_ draft: MailDraft, from id: String) async throws {
        throw LibrusError.readOnly
    }

    func replyRecipients(for id: String) async throws -> MailReplyRecipients {
        .none
    }

    func delete(id: String, permanently: Bool) async throws {
        throw LibrusError.readOnly
    }

    // MARK: Messages session

    private func withMessages<T>(_ operation: () async throws -> T) async throws -> T {
        guard try await requireMessages() else {
            throw LibrusError.moduleUnavailable(endpoint: "wiadomosci", status: 403)
        }
        do {
            return try await operation()
        } catch {
            messagesAvailable = nil
            guard try await requireMessages() else {
                throw error
            }
            return try await operation()
        }
    }

    private func requireMessages() async throws -> Bool {
        let loginCount = await session.loginCount()
        if lastLoginCount != loginCount {
            lastLoginCount = loginCount
            messagesAvailable = nil
        }
        if messagesAvailable == true {
            return true
        }
        if let deniedAt,
           Date().timeIntervalSince(deniedAt) < LibrusConstants.messagesDenialBackoff {
            return false
        }

        let available = (try? await client.bootstrapMessages()) ?? false
        messagesAvailable = available
        deniedAt = available ? nil : Date()
        return available
    }

    // MARK: Mapping

    private func correspondent(for summary: LibrusMessageSummary, kind: MessageKind) -> String {
        switch kind {
        case .received, .deleted:
            return summary.senderName ?? join(summary.senderFirstName, summary.senderLastName)
        case .sent:
            return summary.receiverName ?? join(summary.receiverFirstName, summary.receiverLastName)
        }
    }

    private func detail(from detail: LibrusMessageDetail, fallbackID: String) -> MailMessageDetail {
        let attachments = (detail.attachments ?? []).map { attachment in
            MailAttachment(
                id: attachment.id?.raw ?? UUID().uuidString,
                name: attachment.filename ?? "Załącznik",
                url: nil
            )
        }
        let recipients = (detail.receivers ?? []).compactMap { receiver in
            let name = join(receiver.firstName, receiver.lastName)
            return name.isEmpty ? nil : name
        }

        return MailMessageDetail(
            id: detail.messageId?.raw ?? fallbackID,
            subject: detail.topic ?? "(brak tematu)",
            sender: detail.senderName ?? "",
            recipients: recipients,
            date: detail.sendDate ?? "",
            body: LibrusMessageBody.decode(detail.message),
            attachments: attachments
        )
    }

    private func join(_ first: String?, _ last: String?) -> String {
        [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func mailbox(for kind: MessageKind) -> String {
        switch kind {
        case .received: return "inbox"
        case .sent: return "outbox"
        case .deleted: return "trash"
        }
    }
}
