import SwiftUI

struct HomeworkView: View {
    @Environment(AppModel.self) private var model
    @State private var homework: [Homework] = []
    @State private var weekStart: Date = VulcanDate.startOfWeek(Date())
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    weekHeader
                    if isLoading && homework.isEmpty {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if homework.isEmpty {
                        EmptyStateView(
                            icon: "checklist",
                            title: "Brak zadań w tym tygodniu.",
                            message: "Przejdź do innego tygodnia, aby zobaczyć więcej."
                        )
                    } else {
                        content
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Zadania domowe")
            .dashboardChrome()
            .refreshable { await load() }
            .task(id: model.activeID) { await load() }
        }
    }

    // MARK: - Week header

    private var weekHeader: some View {
        GlassCard {
            HStack(spacing: 12) {
                weekButton("chevron.left", label: "Poprzedni tydzień") {
                    shiftWeek(-1)
                }
                Spacer(minLength: 8)
                VStack(spacing: 2) {
                    Text("Tydzień")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(Palette.onSurfaceVariant)
                    Text(weekRange)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)
                }
                Spacer(minLength: 8)
                weekButton("chevron.right", label: "Następny tydzień") {
                    shiftWeek(1)
                }
            }
        }
    }

    private func weekButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.primary)
                .frame(width: 34, height: 34)
                .background(Palette.secondaryContainer, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Content

    private var content: some View {
        let keys = Array(Set(homework.map(\.deadlineAt))).sorted()
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    Text(VulcanDate.dayLabel(key))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)
                    ForEach(homework.filter { $0.deadlineAt == key }) { item in
                        homeworkCard(item)
                    }
                }
            }
        }
    }

    private func homeworkCard(_ item: Homework) -> some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.subject.name)
                        .font(.headline)
                        .foregroundStyle(Palette.onSurface)
                    Spacer(minLength: 8)
                    if item.isAnswerRequired == true {
                        InfoPill(text: "Odpowiedź wymagana")
                    }
                }
                Text(item.content)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Termin: \(VulcanDate.dayLabel(item.deadlineAt))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Palette.onSurfaceVariant)
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

    private var weekRange: String {
        let end = VulcanDate.addDays(weekStart, 6)
        return "\(VulcanDate.shortLabel(weekStart)) – \(VulcanDate.shortLabel(end))"
    }

    private func shiftWeek(_ delta: Int) {
        weekStart = VulcanDate.startOfWeek(VulcanDate.addDays(weekStart, delta * 7))
        homework = []
        Task { await load() }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        do {
            homework = try await model.loadHomework(weekStart: weekStart)
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}
