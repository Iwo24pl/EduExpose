import SwiftUI

struct ExamsView: View {
    @Environment(AppModel.self) private var model
    @State private var exams: [Exam] = []
    @State private var weekStart: Date = VulcanDate.startOfWeek(Date())
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    weekHeader
                    if isLoading && exams.isEmpty {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if exams.isEmpty {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: "Brak sprawdzianów w tym tygodniu.",
                            message: "Przejdź do innego tygodnia, aby zobaczyć więcej."
                        )
                    } else {
                        content
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Sprawdziany")
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
        let keys = Array(Set(exams.map(\.deadlineAt))).sorted()
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 8) {
                    Text(VulcanDate.dayLabel(key))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)
                    ForEach(exams.filter { $0.deadlineAt == key }) { exam in
                        examCard(exam)
                    }
                }
            }
        }
    }

    private func examCard(_ exam: Exam) -> some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(exam.subject.name)
                        .font(.headline)
                        .foregroundStyle(Palette.onSurface)
                    Spacer(minLength: 8)
                    InfoPill(text: exam.type)
                }
                Text(exam.content)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                if let creator = exam.creator, !creator.displayName.isEmpty {
                    Label(creator.displayName, systemImage: "person")
                        .font(.caption)
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
        exams = []
        Task { await load() }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        do {
            exams = try await model.loadExams(weekStart: weekStart)
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}
