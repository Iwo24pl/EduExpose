import SwiftUI

struct StartView: View {
    @Environment(AppModel.self) private var model
    @State private var snapshot: StartSnapshot?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
            .navigationTitle("Start")
            .dashboardChrome()
            .refreshable { await load() }
            .task(id: model.activeID) { await load() }
        }
    }

    // MARK: - Content

    private func content(_ snapshot: StartSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(snapshot)
            luckyCard(snapshot)
            gradesSection(snapshot)
            examsSection(snapshot)
            homeworkSection(snapshot)
        }
    }

    private func header(_ snapshot: StartSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cześć, \(snapshot.firstName)!")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let account = model.activeAccount {
                HStack(spacing: 8) {
                    InfoPill(text: account.schoolName, icon: "building.2")
                    if let classLabel = account.classLabel {
                        InfoPill(text: classLabel, icon: "person.3")
                    }
                }
                .lineLimit(1)
            }
        }
    }

    private func luckyCard(_ snapshot: StartSnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("Szczęśliwy numerek")
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Palette.onSurfaceVariant)
                if let lucky = snapshot.lucky {
                    Text("\(lucky)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.primary)
                        .contentTransition(.numericText())
                } else {
                    Text("Brak numerka")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private func gradesSection(_ snapshot: StartSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Ostatnie oceny")
            if snapshot.grades.isEmpty {
                EmptyStateView(
                    icon: "graduationcap",
                    title: "Brak ocen",
                    message: "Ostatnio nie pojawiły się żadne oceny."
                )
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.grades) { grade in
                            if snapshot.grades.first?.id != grade.id {
                                Divider()
                            }
                            gradeRow(grade)
                        }
                    }
                }
            }
        }
    }

    private func gradeRow(_ grade: Grade) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.column.subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onSurface)
                if let created = grade.createdAt, !created.isEmpty {
                    Text(VulcanDate.dateTimeLabel(created))
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
                if let comment = grade.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            GradeBadge(text: grade.display, value: grade.numericValue)
        }
    }

    private func examsSection(_ snapshot: StartSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Nadchodzące sprawdziany")
            if snapshot.exams.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "Brak sprawdzianów",
                    message: "Nie ma zaplanowanych sprawdzianów."
                )
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.exams) { exam in
                            if snapshot.exams.first?.id != exam.id {
                                Divider()
                            }
                            examRow(exam)
                        }
                    }
                }
            }
        }
    }

    private func examRow(_ exam: Exam) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exam.subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onSurface)
                Spacer(minLength: 8)
                InfoPill(text: exam.type)
            }
            Text(VulcanDate.dayLabel(exam.deadlineAt))
                .font(.caption)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
    }

    private func homeworkSection(_ snapshot: StartSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Zadania domowe")
            if snapshot.homework.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: "Brak zadań",
                    message: "Nie ma zadań z najbliższych dni."
                )
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.homework) { homework in
                            if snapshot.homework.first?.id != homework.id {
                                Divider()
                            }
                            homeworkRow(homework)
                        }
                    }
                }
            }
        }
    }

    private func homeworkRow(_ homework: Homework) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(homework.subject.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.onSurface)
            Text(homework.content)
                .font(.caption)
                .foregroundStyle(Palette.onSurfaceVariant)
                .lineLimit(2)
            Text("Termin: \(VulcanDate.dayLabel(homework.deadlineAt))")
                .font(.caption2)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        error = nil
        do {
            snapshot = try await model.loadStart()
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}
