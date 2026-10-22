import SwiftUI

struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var notes: [Note] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading && notes.isEmpty {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if sortedNotes.isEmpty {
                        EmptyStateView(
                            icon: "note.text",
                            title: "Brak notatek",
                            message: "Nie ma jeszcze żadnych uwag ani pochwał."
                        )
                    } else {
                        content
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Notatki")
            .dashboardChrome()
            .refreshable { await load() }
            .task(id: model.activeID) { await load() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sortedNotes) { note in
                noteCard(note)
            }
        }
    }

    private func noteCard(_ note: Note) -> some View {
        GlassCard(cornerRadius: 22) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.positive ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(note.positive ? Palette.success : Palette.error)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(note.category?.name ?? "Notatka")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.onSurface)
                        Spacer(minLength: 8)
                        if let points = note.points {
                            InfoPill(text: "\(points) pkt")
                        }
                    }
                    Text(note.content)
                        .font(.subheadline)
                        .foregroundStyle(Palette.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let creator = note.creator, !creator.displayName.isEmpty {
                            Text(creator.displayName)
                            Text("•")
                        }
                        Text(VulcanDate.dayLabel(note.validAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
        }
    }

    private var sortedNotes: [Note] {
        notes.sorted { $0.validAt > $1.validAt }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        do {
            notes = try await model.loadNotes()
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}
