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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Skrzynka", selection: $kind) {
                        ForEach(MessageKind.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let message = model.errorMessage {
                        ErrorBanner(message: message)
                    }

                    if isLoading && messages.isEmpty {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if messages.isEmpty {
                        EmptyStateView(
                            icon: "envelope",
                            title: "Brak wiadomości",
                            message: emptyMessage
                        )
                    } else {
                        list
                    }
                }
                .padding(20)
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
            .refreshable { await load() }
            .task(id: model.activeID) {
                // Never show the previous pupil's mail while the new one loads.
                messages = []
                locallyRead = []
                error = nil
                await loadCapabilities()
                guard !Task.isCancelled else { return }
                await load()
            }
            .onChange(of: kind) { _, _ in
                messages = []
                error = nil
                Task { await load() }
            }
            .sheet(item: $sheet, onDismiss: { Task { await load() } }) { item in
                switch item {
                case .detail(let message):
                    MessageDetailView(
                        message: message,
                        kind: kind,
                        mailboxes: mailboxes,
                        canSend: canSend,
                        onRead: { id in _ = locallyRead.insert(id) }
                    )
                case .compose(let context):
                    ComposeMessageView(context: context, mailboxes: mailboxes)
                }
            }
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
        VStack(spacing: 10) {
            ForEach(messages) { message in
                Button {
                    sheet = .detail(message)
                } label: {
                    messageRow(message)
                }
                .buttonStyle(.plain)
            }
        }
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
        guard model.canSendMessages else {
            canSend = false
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
            recipients: [],
            subject: "",
            body: ""
        ))
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

    @State private var detail: MailMessageDetail?
    @State private var compose: ComposeContext?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        ErrorBanner(message: error)
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
                    if canSend {
                        Menu {
                            Button {
                                openCompose(.reply)
                            } label: {
                                Label("Odpowiedz", systemImage: "arrowshape.turn.up.left")
                            }
                            Button {
                                openCompose(.reply, all: true)
                            } label: {
                                Label("Odpowiedz wszystkim", systemImage: "arrowshape.turn.up.left.2")
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

        compose = ComposeContext(
            mode: mode,
            original: message,
            recipients: recipients(for: mode, all: all),
            subject: subject,
            body: quotedBody
        )
    }

    private func recipients(for mode: MailSendMode, all: Bool) -> [Mailbox] {
        guard mode != .forward, let detail else { return [] }
        var result: [Mailbox] = []
        if let sender = matchingMailbox(detail.sender) {
            result.append(sender)
        }
        if all {
            for name in detail.recipients {
                if let box = matchingMailbox(name),
                   !result.contains(where: { $0.id == box.id }) {
                    result.append(box)
                }
            }
        }
        return result
    }

    /// Recipient names come from the server, so only resolve a mailbox when the
    /// match is exact or unambiguous. Guessing here sends mail to the wrong person.
    private func matchingMailbox(_ name: String) -> Mailbox? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let exact = mailboxes.first(where: {
            $0.displayName.compare(target, options: options) == .orderedSame
                || $0.name.compare(target, options: options) == .orderedSame
        }) {
            return exact
        }

        let candidates = mailboxes.filter { box in
            let display = box.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { return false }
            return Self.wordsContained(display, in: target)
                || Self.wordsContained(target, in: display)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// True when every word of `needle` appears as a whole word in `haystack`.
    private static func wordsContained(_ needle: String, in haystack: String) -> Bool {
        let words = haystack
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let needles = needle
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !needles.isEmpty, !words.isEmpty else { return false }
        return needles.allSatisfy { word in
            words.contains {
                $0.compare(
                    word,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
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
    let recipients: [Mailbox]
    let subject: String
    let body: String
}

private struct ComposeMessageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let context: ComposeContext
    let mailboxes: [Mailbox]

    @State private var recipients: [Mailbox]
    @State private var subject: String
    @State private var bodyText: String
    @State private var showRecipientPicker = false
    @State private var isSending = false
    @State private var error: String?

    init(context: ComposeContext, mailboxes: [Mailbox]) {
        self.context = context
        self.mailboxes = mailboxes
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

                    SectionTitle(title: "Odbiorcy")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            if recipients.isEmpty {
                                Text("Dodaj co najmniej jednego odbiorcę.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                            ForEach(recipients) { box in
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundStyle(Palette.primary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(box.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(Palette.onSurface)
                                        if let detail = box.detail {
                                            Text(detail)
                                                .font(.caption2)
                                                .foregroundStyle(Palette.onSurfaceVariant)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        recipients.removeAll { $0.id == box.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Palette.onSurfaceVariant)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Usuń odbiorcę")
                                }
                            }
                            Button {
                                showRecipientPicker = true
                            } label: {
                                Label("Dodaj odbiorcę", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                            .tint(Palette.primary)
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
                RecipientPickerView(mailboxes: mailboxes, selected: $recipients)
            }
            .interactiveDismissDisabled(isSending)
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
                body: bodyText
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
    let mailboxes: [Mailbox]
    @Binding var selected: [Mailbox]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filtered) { box in
                Button {
                    toggle(box)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(box.displayName)
                                .foregroundStyle(Palette.onSurface)
                            if let detail = box.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                        Spacer(minLength: 0)
                        if selected.contains(where: { $0.id == box.id }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
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

    private var filtered: [Mailbox] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return mailboxes }
        return mailboxes.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.displayName.localizedCaseInsensitiveContains(text)
        }
    }

    private func toggle(_ box: Mailbox) {
        if let index = selected.firstIndex(where: { $0.id == box.id }) {
            selected.remove(at: index)
        } else {
            selected.append(box)
        }
    }
}
