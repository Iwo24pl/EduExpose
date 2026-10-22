import SwiftUI

struct AnnouncementsView: View {
    @Environment(AppModel.self) private var model
    @State private var announcements: [Announcement] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading && announcements.isEmpty {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if sortedAnnouncements.isEmpty {
                        EmptyStateView(
                            icon: "megaphone",
                            title: "Brak ogłoszeń",
                            message: "Nie ma nowych ogłoszeń ze szkoły."
                        )
                    } else {
                        content
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Ogłoszenia")
            .dashboardChrome()
            .refreshable { await load() }
            .task(id: model.activeID) { await load() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sortedAnnouncements) { item in
                announcementCard(item)
            }
        }
    }

    private func announcementCard(_ item: Announcement) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Palette.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let sender = item.sender, !sender.displayName.isEmpty {
                        Text(sender.displayName)
                    }
                    if let created = item.createdAt, !created.isEmpty {
                        if item.sender != nil {
                            Text("•")
                        }
                        Text(VulcanDate.dateTimeLabel(created))
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.onSurfaceVariant)
                Text(item.content)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                if let attachments = item.attachments, !attachments.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "paperclip")
                        Text(attachments.map { $0.name }.joined(separator: ", "))
                            .lineLimit(2)
                    }
                    .font(.caption2)
                    .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
        }
    }

    private var sortedAnnouncements: [Announcement] {
        announcements.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        do {
            announcements = try await model.loadAnnouncements()
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}
