import SwiftUI

struct GradesView: View {
    @Environment(AppModel.self) private var model
    @State private var snapshot: GradesSnapshot?
    @State private var period: Period?
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedGrade: Grade?

    private var periods: [Period] {
        model.activeAccount?.periods ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if periods.count > 1 {
                        periodMenu
                    }
                    if isLoading && snapshot == nil {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if let snapshot {
                        content(snapshot)
                    } else {
                        LoadingView()
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Oceny")
            .dashboardChrome()
            .refreshable { await load() }
            .task(id: model.activeID) { await loadInitial() }
            .sheet(item: $selectedGrade) { grade in
                GradeDetailSheet(grade: grade)
            }
        }
    }

    // MARK: - Period

    private var periodMenu: some View {
        Menu {
            ForEach(periods) { item in
                Button {
                    guard item.id != period?.id else { return }
                    period = item
                    snapshot = nil
                    Task { await load() }
                } label: {
                    if item.id == period?.id {
                        Label(periodTitle(item), systemImage: "checkmark")
                    } else {
                        Text(periodTitle(item))
                    }
                }
            }
        } label: {
            InfoPill(text: periodTitle(period), icon: "chevron.down")
        }
        .tint(Palette.onSurface)
    }

    private func periodTitle(_ item: Period?) -> String {
        guard let item else { return "Okres" }
        if let number = item.number {
            return "Okres \(number)"
        }
        return "Okres"
    }

    // MARK: - Content

    private func content(_ snapshot: GradesSnapshot) -> some View {
        let groups = Dictionary(grouping: snapshot.grades, by: { $0.column.subject.id })
        let subjects = groups
            .compactMap { $0.value.first?.column.subject }
            .sorted { ($0.position ?? 999) < ($1.position ?? 999) }

        return VStack(alignment: .leading, spacing: 14) {
            if snapshot.grades.isEmpty {
                EmptyStateView(
                    icon: "graduationcap",
                    title: "Brak ocen",
                    message: "W tym okresie nie ma jeszcze żadnych ocen."
                )
            } else {
                ForEach(subjects) { subject in
                    subjectCard(
                        subject: subject,
                        grades: groups[subject.id] ?? [],
                        averages: snapshot.averages
                    )
                }
            }
        }
    }

    private func subjectCard(subject: Subject, grades: [Grade], averages: [GradeAverage]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(Palette.onSurface)
                    Spacer(minLength: 8)
                    if let average = averages.first(where: { $0.subject.id == subject.id })?.average,
                       !average.isEmpty {
                        InfoPill(text: "Śr. \(average)", icon: "chart.line.uptrend.xyaxis")
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(grades) { grade in
                        Button {
                            selectedGrade = grade
                        } label: {
                            GradeBadge(text: grade.display, value: grade.numericValue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadInitial() async {
        period = model.activeAccount?.currentPeriod
        snapshot = nil
        await load()
    }

    private func load() async {
        guard let currentPeriod = period else {
            isLoading = false
            error = "Konto nie ma aktywnego okresu."
            return
        }
        isLoading = true
        error = nil
        do {
            snapshot = try await model.loadGrades(period: currentPeriod)
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}

// MARK: - Detail

private struct GradeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let grade: Grade

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        GradeBadge(text: grade.display, value: grade.numericValue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(grade.column.subject.name)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.onSurface)
                            if !grade.column.name.isEmpty {
                                Text(grade.column.name)
                                    .font(.caption)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow("Treść", grade.content ?? "")
                            detailRow("Kategoria", grade.column.category?.name ?? "—")
                            detailRow("Waga", grade.column.weight.map { $0.clean } ?? "—")
                            detailRow("Data", dateText)
                            if let corrected = grade.correctedGrade, !corrected.isEmpty {
                                detailRow("Poprawiona", corrected)
                            }
                        }
                    }

                    if let comment = grade.comment, !comment.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(title: "Komentarz")
                            GlassCard {
                                Text(comment)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.onSurface)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Szczegóły oceny")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                BrandBackdrop()
                    .opacity(0.6)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var dateText: String {
        guard let created = grade.createdAt, !created.isEmpty else { return "—" }
        return VulcanDate.dateTimeLabel(created)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.onSurfaceVariant)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundStyle(Palette.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
