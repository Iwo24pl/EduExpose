import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: MessageKind = .received
    @State private var messages: [Message] = []
    @State private var locallyRead: Set<String> = []
    @State private var selectedMessage: Message?
    @State private var isLoading = false
    @State private var error: String?

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
            .refreshable { await load() }
            .task(id: model.activeID) { await load() }
            .onChange(of: kind) { _, _ in
                messages = []
                error = nil
                Task { await load() }
            }
            .sheet(item: $selectedMessage) { message in
                MessageDetailView(message: message, kind: kind)
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
                    locallyRead.insert(message.id)
                    selectedMessage = message
                } label: {
                    messageRow(message)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func messageRow(_ message: Message) -> some View {
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
                    Text(participant(message))
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                    Text(VulcanDate.dateTimeLabel(message.sentAt))
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                if message.withdrawn == true {
                    InfoPill(text: "Wycofana")
                }
            }
        }
    }

    private func isUnread(_ message: Message) -> Bool {
        kind == .received && message.status == 0 && !locallyRead.contains(message.id)
    }

    private func participant(_ message: Message) -> String {
        switch kind {
        case .received:
            return message.sender.name
        case .sent, .deleted:
            let names = (message.receiver ?? []).map { $0.name }
            return names.isEmpty ? message.sender.name : names.joined(separator: ", ")
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        do {
            messages = try await model.loadMessages(kind: kind)
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}

// MARK: - Detail

private struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let message: Message
    let kind: MessageKind

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.errorMessage {
                        ErrorBanner(message: error)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.subject)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(message.sender.name)
                            Text("•")
                            Text(VulcanDate.dateTimeLabel(message.sentAt))
                        }
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        if let receivers = message.receiver, !receivers.isEmpty {
                            Text("Do: " + receivers.map { $0.name }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Palette.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if message.withdrawn == true {
                        InfoPill(text: "Wiadomość wycofana")
                    }

                    GlassCard {
                        Text(message.content)
                            .font(.subheadline)
                            .foregroundStyle(Palette.onSurface)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let attachments = message.attachments, !attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(title: "Załączniki")
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(attachments.indices, id: \.self) { index in
                                        attachmentRow(attachments[index])
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if kind == .received && message.status == 0 {
                await model.markRead(message)
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: Attachment) -> some View {
        if let link = attachment.link, let url = URL(string: link) {
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
