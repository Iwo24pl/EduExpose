import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: MessageKind = .received
    @State private var messages: [MailMessage] = []
    @State private var locallyRead: Set<String> = []
    @State private var sheet: MessageSheet?
    @State private var mailboxes: [Mailbox] = []
    @State private var canSend = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var actionError: String?
    @State private var pendingPermanentDelete: MailMessage?
    @State private var isConfirmingPermanentDelete = false
    @State private var deletingIDs: Set<String> = []
    @State private var loadGeneration = 0

    /// One presentation slot: two `.sheet` modifiers on the same view only
    /// present reliably on some iOS versions.
    private enum MessageSheet: Identifiable {
        case detail(MailMessage)
        case compose(ComposeContext)

        var id: String {
            switch self {
            case .detail(let message): return "detail-\(message.id)"
            case .compose(let context): return "compose-\(context.id.uuidString)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Skrzynka", selection: $kind) {
                    ForEach(MessageKind.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 4)

                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                        .padding(.horizontal, 20)
                }

                if let actionError {
                    ErrorBanner(message: actionError)
                        .padding(.horizontal, 20)
                }

                content
            }
            .background(ScreenBackground())
            .navigationTitle("Wiadomości")
            .dashboardChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await openNewMessage() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(Palette.primary)
                    .disabled(!canSend)
                    .accessibilityLabel("Nowa wiadomość")
                }
            }
            .task(id: model.activeID) {
                // Never show the previous pupil's mail while the new one loads.
                messages = []
                locallyRead = []
                error = nil
                actionError = nil
                await loadCapabilities()
                guard !Task.isCancelled else { return }
                await load()
            }
            .onChange(of: kind) { _, _ in
                messages = []
                error = nil
                actionError = nil
                Task { await load() }
            }
            .confirmationDialog(
                "Usunąć wiadomość trwale?",
                isPresented: $isConfirmingPermanentDelete,
                presenting: pendingPermanentDelete
            ) { message in
                Button("Usuń trwale", role: .destructive) {
                    Task { await delete(message, permanently: true) }
                }
                Button("Anuluj", role: .cancel) {}
            } message: { message in
                Text("„\(message.subject)” zostanie usunięta bez możliwości przywrócenia.")
            }
            .sheet(item: $sheet, onDismiss: { Task { await load() } }) { item in
                switch item {
                case .detail(let message):
                    MessageDetailView(
                        message: message,
                        kind: kind,
                        mailboxes: mailboxes,
                        canSend: canSend,
                        onRead: { id in _ = locallyRead.insert(id) },
                        onDelete: { id in
                            withAnimation { messages.removeAll { $0.id == id } }
                        }
                    )
                case .compose(let context):
                    ComposeMessageView(context: context, mailboxes: mailboxes)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && messages.isEmpty {
            ScrollView {
                LoadingView()
                    .padding(20)
            }
            .refreshable { await load() }
        } else if let error {
            ScrollView {
                ErrorStateView(message: error) {
                    Task { await load() }
                }
                .padding(20)
            }
            .refreshable { await load() }
        } else if messages.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "envelope",
                    title: "Brak wiadomości",
                    message: emptyMessage
                )
                .padding(20)
            }
            .refreshable { await load() }
        } else {
            list
        }
    }

    private var emptyMessage: String {
        switch kind {
        case .received: return "Nie ma odebranych wiadomości."
        case .sent: return "Nie wysłano jeszcze żadnych wiadomości."
        case .deleted: return "Kosz jest pusty."
        }
    }

    private var list: some View {
        List {
            ForEach(messages) { message in
                Button {
                    sheet = .detail(message)
                } label: {
                    messageRow(message)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canSend {
                        Button(role: .destructive) {
                            requestDelete(message)
                        } label: {
                            Label(
                                kind == .deleted ? "Usuń trwale" : "Usuń",
                                systemImage: "trash"
                            )
                        }
                        .disabled(deletingIDs.contains(message.id))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func messageRow(_ message: MailMessage) -> some View {
        GlassCard(cornerRadius: 22) {
            HStack(alignment: .top, spacing: 10) {
                if isUnread(message) {
                    Circle()
                        .fill(Palette.primary)
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(message.correspondent)
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                    Text(VulcanDate.dateTimeLabel(message.date))
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                if message.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func isUnread(_ message: MailMessage) -> Bool {
        kind == .received && message.isUnread && !locallyRead.contains(message.id)
    }

    // MARK: - Loading

    private func loadCapabilities() async {
        canSend = model.mailCapabilities.canCompose
        guard canSend else {
            mailboxes = []
            return
        }
        do {
            mailboxes = try await model.loadMailboxes()
            canSend = !mailboxes.isEmpty
        } catch {
            mailboxes = []
            canSend = false
        }
    }

    private func openNewMessage() async {
        if mailboxes.isEmpty {
            await loadCapabilities()
        }
        guard !mailboxes.isEmpty else {
            error = "Nie udało się pobrać listy skrzynek."
            return
        }
        sheet = .compose(ComposeContext(
            mode: .new,
            original: nil,
            replyNames: [],
            recipients: [],
            sender: model.defaultSender(in: mailboxes),
            subject: "",
            body: ""
        ))
    }

    // MARK: - Deletion

    /// First delete moves the message to `Kosz`; deleting it there is final and
    /// asks for confirmation.
    private func requestDelete(_ message: MailMessage) {
        actionError = nil
        if kind == .deleted {
            pendingPermanentDelete = message
            isConfirmingPermanentDelete = true
        } else {
            Task { await delete(message, permanently: false) }
        }
    }

    private func delete(_ message: MailMessage, permanently: Bool) async {
        guard !deletingIDs.contains(message.id) else { return }
        deletingIDs.insert(message.id)
        let snapshot = messages
        withAnimation { messages.removeAll { $0.id == message.id } }
        do {
            try await model.deleteMessage(id: message.id, permanently: permanently)
            await load()
        } catch {
            withAnimation { messages = snapshot }
            actionError = AppModel.describe(error)
        }
        deletingIDs.remove(message.id)
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedKind = kind
        isLoading = true
        error = nil
        do {
            let loaded = try await model.loadMessages(kind: requestedKind)
            guard generation == loadGeneration, requestedKind == kind else { return }
            messages = loaded
        } catch {
            guard generation == loadGeneration, requestedKind == kind else { return }
            self.error = AppModel.describe(error)
        }
        if generation == loadGeneration {
            isLoading = false
        }
    }
}

// MARK: - Detail

private struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let message: MailMessage
    let kind: MessageKind
    let mailboxes: [Mailbox]
    let canSend: Bool
    let onRead: (String) -> Void
    let onDelete: (String) -> Void

    @State private var detail: MailMessageDetail?
    @State private var compose: ComposeContext?
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?
    @State private var isDeleting = false
    @State private var isConfirmingDelete = false
    @State private var isPreparingCompose = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        ErrorBanner(message: error)
                    }

                    if let actionError {
                        ErrorBanner(message: actionError)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail?.subject ?? message.subject)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(detail?.sender ?? message.correspondent)
                            Text("•")
                            Text(VulcanDate.dateTimeLabel(detail?.date ?? message.date))
                        }
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        if let detail, !detail.recipients.isEmpty {
                            Text("Do: " + detail.recipients.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Palette.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isLoading {
                        LoadingView()
                    } else {
                        GlassCard {
                            Text(bodyText)
                                .font(.subheadline)
                                .foregroundStyle(Palette.onSurface)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let attachments = detail?.attachments, !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(title: "Załączniki")
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(attachments) { attachment in
                                        attachmentRow(attachment)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Wiadomość")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isPreparingCompose {
                        ProgressView()
                    } else if canSend {
                        HStack(spacing: 14) {
                            Button {
                                if kind == .deleted {
                                    isConfirmingDelete = true
                                } else {
                                    Task { await deleteMessage() }
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(kind == .deleted ? Palette.error : Palette.primary)
                            .disabled(isDeleting)
                            .accessibilityLabel(kind == .deleted ? "Usuń trwale" : "Usuń")

                            Menu {
                                Button {
                                    openCompose(.reply)
                                } label: {
                                    Label("Odpowiedz", systemImage: "arrowshape.turn.up.left")
                                }
                                Button {
                                    openCompose(.reply, all: true)
                                } label: {
                                    Label(
                                        "Odpowiedz wszystkim",
                                        systemImage: "arrowshape.turn.up.left.2"
                                    )
                                }
                                Button {
                                    openCompose(.forward)
                                } label: {
                                    Label("Przekaż", systemImage: "arrowshape.turn.up.right")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .tint(Palette.primary)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Usunąć wiadomość trwale?",
                isPresented: $isConfirmingDelete
            ) {
                Button("Usuń trwale", role: .destructive) {
                    Task { await deleteMessage() }
                }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("„\(detail?.subject ?? message.subject)” zostanie usunięta bez możliwości przywrócenia.")
            }
            .sheet(item: $compose) { context in
                ComposeMessageView(context: context, mailboxes: mailboxes)
            }
            .task(id: message.id) {
                await loadDetail()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var bodyText: String {
        let text = detail?.body ?? message.inlineBody ?? ""
        return text.isEmpty ? "Brak treści wiadomości." : text
    }

    private func loadDetail() async {
        isLoading = true
        error = nil
        do {
            detail = try await model.loadMessageDetail(id: message.id)
            if kind == .received && message.isUnread {
                await model.markRead(id: message.id)
                // Only hide the unread dot once the message was opened.
                onRead(message.id)
            }
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }

    private func deleteMessage() async {
        guard !isDeleting else { return }
        isDeleting = true
        actionError = nil
        do {
            try await model.deleteMessage(id: message.id, permanently: kind == .deleted)
            onDelete(message.id)
            dismiss()
        } catch {
            actionError = AppModel.describe(error)
        }
        isDeleting = false
    }

    private func openCompose(_ mode: MailSendMode, all: Bool = false) {
        guard canSend else { return }
        guard !mailboxes.isEmpty else {
            error = "Nie udało się pobrać listy odbiorców."
            return
        }

        let baseSubject = detail?.subject ?? message.subject
        let subject: String
        switch mode {
        case .reply:
            subject = baseSubject.lowercased().hasPrefix("re:")
                ? baseSubject
                : "Re: \(baseSubject)"
        case .forward:
            subject = baseSubject.lowercased().hasPrefix("fwd:")
                ? baseSubject
                : "Fwd: \(baseSubject)"
        case .new:
            subject = ""
        }

        let quotedBody: String
        if mode == .forward, let detail {
            quotedBody = """


            --- Wiadomość oryginalna ---
            Od: \(detail.sender)
            Data: \(VulcanDate.dateTimeLabel(detail.date))
            Temat: \(detail.subject)

            \(detail.body)
            """
        } else {
            quotedBody = ""
        }

        let names = replyNames(mode: mode, all: all)
        isPreparingCompose = true
        Task {
            var recipients: [MailContact] = []
            if mode != .forward {
                do {
                    recipients = resolvedRecipients(
                        try await model.replyRecipients(for: message.id),
                        all: all
                    )
                } catch {
                    // The compose screen matches the displayed names against the
                    // address books instead of guessing mailbox keys.
                    recipients = []
                }
            }
            compose = ComposeContext(
                mode: mode,
                original: message,
                replyNames: names,
                recipients: recipients,
                sender: model.defaultSender(in: mailboxes),
                subject: subject,
                body: quotedBody
            )
            isPreparingCompose = false
        }
    }

    /// Raw names shown by the server; used only when the reply lookup fails.
    private func replyNames(mode: MailSendMode, all: Bool) -> [String] {
        guard mode != .forward else { return [] }
        var names: [String] = []
        if let sender = detail?.sender, !sender.isEmpty {
            names.append(sender)
        }
        if all {
            names.append(contentsOf: detail?.recipients ?? [])
        }
        return names
    }

    private func resolvedRecipients(
        _ reply: MailReplyRecipients,
        all: Bool
    ) -> [MailContact] {
        var candidates: [MailContact] = []
        if let sender = reply.sender {
            candidates.append(sender)
        }
        if all {
            candidates.append(contentsOf: reply.recipients)
        }

        let own = Set(mailboxes.map(\.globalKey))
        var seen = Set<String>()
        return candidates.filter { contact in
            !own.contains(contact.globalKey) && seen.insert(contact.globalKey).inserted
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: MailAttachment) -> some View {
        if let url = attachment.url {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text(attachment.name)
                        .underline()
                }
                .font(.caption)
            }
            .tint(Palette.primary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                Text(attachment.name)
            }
            .font(.caption)
            .foregroundStyle(Palette.onSurfaceVariant)
        }
    }
}

// MARK: - Compose

private struct ComposeContext: Identifiable {
    let id = UUID()
    let mode: MailSendMode
    let original: MailMessage?
    /// Raw server names, used only when the reply lookup produced no keys.
    let replyNames: [String]
    let recipients: [MailContact]
    let sender: Mailbox?
    let subject: String
    let body: String
}

private struct ComposeMessageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let context: ComposeContext
    let mailboxes: [Mailbox]

    @State private var sender: Mailbox?
    @State private var recipients: [MailContact]
    @State private var contacts: [MailContact] = []
    @State private var isLoadingContacts = false
    @State private var contactsError: String?
    @State private var subject: String
    @State private var bodyText: String
    @State private var showRecipientPicker = false
    @State private var isSending = false
    @State private var error: String?

    init(context: ComposeContext, mailboxes: [Mailbox]) {
        self.context = context
        self.mailboxes = mailboxes
        _sender = State(initialValue: context.sender ?? mailboxes.first)
        _recipients = State(initialValue: context.recipients)
        _subject = State(initialValue: context.subject)
        _bodyText = State(initialValue: context.body)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        ErrorBanner(message: error)
                    }

                    SectionTitle(title: "Od")
                    GlassCard {
                        senderRow
                    }

                    SectionTitle(title: "Odbiorcy")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            if recipients.isEmpty {
                                Text("Dodaj co najmniej jednego odbiorcę.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                            ForEach(recipients) { contact in
                                recipientRow(contact)
                            }
                            Button {
                                showRecipientPicker = true
                            } label: {
                                Label("Dodaj odbiorcę", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                            .tint(Palette.primary)

                            if isLoadingContacts {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Pobieranie kontaktów…")
                                }
                                .font(.caption)
                                .foregroundStyle(Palette.onSurfaceVariant)
                            } else if let contactsError {
                                Text(contactsError)
                                    .font(.caption)
                                    .foregroundStyle(Palette.error)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SectionTitle(title: "Temat")
                    GlassCard {
                        TextField("Temat", text: $subject)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Palette.onSurface)
                            .tint(Palette.primary)
                            .textInputAutocapitalization(.sentences)
                    }

                    SectionTitle(title: "Treść")
                    GlassCard {
                        TextEditor(text: $bodyText)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .foregroundStyle(Palette.onSurface)
                            .tint(Palette.primary)
                            .frame(minHeight: 190)
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Wyślij") {
                            Task { await send() }
                        }
                        .disabled(recipients.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showRecipientPicker) {
                RecipientPickerView(
                    contacts: contacts,
                    isLoading: isLoadingContacts,
                    error: contactsError,
                    retry: { Task { await loadContacts() } },
                    selected: $recipients
                )
            }
            .task(id: sender?.id) {
                contacts = []
                await loadContacts()
            }
            .interactiveDismissDisabled(isSending)
        }
    }

    private var senderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperplane.circle")
                .foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(sender?.displayName ?? "Brak skrzynki")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                if let detail = sender?.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            if mailboxes.count > 1 {
                Menu {
                    ForEach(mailboxes) { box in
                        Button {
                            sender = box
                        } label: {
                            if box.id == sender?.id {
                                Label(box.displayName, systemImage: "checkmark")
                            } else {
                                Text(box.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Zmień")
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.primary)
                }
                .accessibilityLabel("Zmień skrzynkę nadawcy")
            }
        }
    }

    private func recipientRow(_ contact: MailContact) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(Palette.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.displayName)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                if let detail = contact.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            Button {
                recipients.removeAll { $0.globalKey == contact.globalKey }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Usuń odbiorcę")
        }
    }

    // MARK: Contacts

    private func loadContacts() async {
        let requested = sender?.id
        isLoadingContacts = true
        contactsError = nil
        do {
            let loaded = try await model.loadContacts(sender: sender)
            guard !Task.isCancelled, sender?.id == requested else { return }
            contacts = loaded
            prefillIfNeeded(loaded)
            isLoadingContacts = false
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, sender?.id == requested else { return }
            contacts = []
            contactsError = AppModel.describe(error)
            isLoadingContacts = false
        }
    }

    /// Fallback when the reply lookup could not resolve mailbox keys: match the
    /// names shown by the server against the exact address-book entries.
    private func prefillIfNeeded(_ loaded: [MailContact]) {
        guard recipients.isEmpty, !context.replyNames.isEmpty else { return }

        let exact = loaded.filter { context.replyNames.contains($0.name) }
        let candidates: [MailContact]
        if exact.isEmpty {
            // Only an unambiguous display-name match is safe to prefill.
            var resolved: [MailContact] = []
            for raw in context.replyNames {
                let name = VulcanMailboxName.parse(raw)?.name ?? raw
                let matches = loaded.filter { $0.displayName == name }
                if matches.count == 1 {
                    resolved.append(matches[0])
                }
            }
            candidates = resolved
        } else {
            candidates = exact
        }

        let own = Set(mailboxes.map(\.globalKey))
        var seen = Set<String>()
        recipients = candidates.filter { contact in
            !own.contains(contact.globalKey) && seen.insert(contact.globalKey).inserted
        }
    }

    private var title: String {
        switch context.mode {
        case .new: return "Nowa wiadomość"
        case .reply: return "Odpowiedz"
        case .forward: return "Przekaż"
        }
    }

    private func send() async {
        guard !recipients.isEmpty else {
            error = "Wybierz co najmniej jednego odbiorcę."
            return
        }
        isSending = true
        error = nil
        do {
            let draft = MailDraft(
                recipients: recipients,
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                body: bodyText,
                sender: sender
            )
            try await model.sendMessage(
                draft,
                mode: context.mode,
                originalID: context.original?.id
            )
            dismiss()
        } catch {
            self.error = AppModel.describe(error)
        }
        isSending = false
    }
}

private struct RecipientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let contacts: [MailContact]
    let isLoading: Bool
    let error: String?
    let retry: () -> Void
    @Binding var selected: [MailContact]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ScreenBackground())
                .searchable(text: $query, prompt: "Szukaj odbiorcy")
                .navigationTitle("Odbiorcy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Gotowe") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && contacts.isEmpty {
            LoadingView()
        } else if contacts.isEmpty, let error {
            ScrollView {
                ErrorStateView(message: error, retry: retry)
                    .padding(20)
            }
        } else if contacts.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "person.2.slash",
                    title: "Brak kontaktów",
                    message: "Ta skrzynka nie zwróciła żadnych adresów."
                )
                .padding(20)
            }
        } else if filtered.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Brak wyników",
                    message: "Żaden kontakt nie pasuje do wyszukiwania."
                )
                .padding(20)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(MailContactRole.allCases) { role in
                let items = filtered.filter { $0.role == role }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { contact in
                            Button {
                                toggle(contact)
                            } label: {
                                row(contact)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(role.groupTitle)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ contact: MailContact) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .foregroundStyle(Palette.onSurface)
                if let detail = contact.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            if selected.contains(where: { $0.globalKey == contact.globalKey }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.primary)
            }
        }
    }

    private var filtered: [MailContact] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return contacts }
        return contacts.filter { contact in
            contact.displayName.localizedStandardContains(text)
                || contact.name.localizedStandardContains(text)
                || (contact.school?.localizedStandardContains(text) ?? false)
        }
    }

    private func toggle(_ contact: MailContact) {
        if let index = selected.firstIndex(where: { $0.globalKey == contact.globalKey }) {
            selected.remove(at: index)
        } else {
            selected.append(contact)
        }
    }
}
