import SwiftUI

struct TimetableView: View {
    @Environment(AppModel.self) private var model
    @State private var schedules: [Schedule] = []
    @State private var weekStart: Date = VulcanDate.startOfWeek(Date())
    @State private var selectedDay: Date = TimetableView.initialDay()
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    weekHeader
                    if isLoading && schedules.isEmpty {
                        LoadingView()
                    } else if let error {
                        ErrorStateView(message: error) {
                            Task { await load() }
                        }
                    } else if lessons.isEmpty {
                        EmptyStateView(
                            icon: "calendar",
                            title: "Brak lekcji tego dnia.",
                            message: "Sprawdź inny dzień lub odśwież plan."
                        )
                    } else {
                        lessonsList
                    }
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Plan")
            .dashboardChrome()
            .refreshable { await load() }
            .task(id: model.activeID) { await load() }
        }
    }

    // MARK: - Week header

    private var weekHeader: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
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
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { index in
                        dayButton(offset: index)
                    }
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

    private func dayButton(offset: Int) -> some View {
        let day = VulcanDate.addDays(weekStart, offset)
        let isSelected = VulcanDate.dateString(day) == VulcanDate.dateString(selectedDay)
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text(VulcanDate.weekdayShort(day))
                    .font(.caption2.weight(.semibold))
                Text("\(VulcanDate.calendar.component(.day, from: day))")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(isSelected ? Palette.onPrimaryContainer : Palette.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? Palette.primaryContainer : Palette.secondaryContainer.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VulcanDate.label(day))
    }

    // MARK: - Lessons

    private var lessonsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: VulcanDate.label(selectedDay))
            ForEach(lessons) { item in
                lessonCard(item)
            }
        }
    }

    private func lessonCard(_ item: Schedule) -> some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Text(timeRange(item.effectiveSlot))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .frame(width: 88, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.effectiveSubject?.name ?? item.event ?? "Lekcja")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.isCanceled ? Palette.onSurfaceVariant : Palette.onSurface)
                            .strikethrough(item.isCanceled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if let room = item.effectiveRoom?.code, !room.isEmpty {
                                Label(room, systemImage: "door.left.hand.open")
                            }
                            if let teacher = item.effectiveTeacher?.displayName, !teacher.isEmpty {
                                Text(teacher)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if item.isCanceled || item.isRescheduled || item.substitution != nil {
                    HStack(spacing: 6) {
                        if item.isCanceled {
                            InfoPill(text: "Odwołane")
                        }
                        if item.isRescheduled {
                            InfoPill(text: "Przeniesione")
                        }
                        if item.substitution != nil {
                            InfoPill(text: "Zastępstwo")
                        }
                    }
                }
                if let note = item.noteOrReason, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lessons: [Schedule] {
        let key = VulcanDate.dateString(selectedDay)
        var bySlot: [Int: Schedule] = [:]
        for item in schedules where item.effectiveDate == key {
            let position = item.effectiveSlot.position
            if let existing = bySlot[position] {
                if item.substitution != nil && existing.substitution == nil {
                    bySlot[position] = item
                }
            } else {
                bySlot[position] = item
            }
        }
        return bySlot.values.sorted { $0.effectiveSlot.position < $1.effectiveSlot.position }
    }

    private func timeRange(_ slot: Timeslot) -> String {
        "\(VulcanDate.time(slot.start))–\(VulcanDate.time(slot.end))"
    }

    private var weekRange: String {
        let end = VulcanDate.addDays(weekStart, 6)
        return "\(VulcanDate.shortLabel(weekStart)) – \(VulcanDate.shortLabel(end))"
    }

    private func shiftWeek(_ delta: Int) {
        let next = VulcanDate.startOfWeek(VulcanDate.addDays(weekStart, delta * 7))
        weekStart = next
        selectedDay = VulcanDate.addDays(selectedDay, delta * 7)
        schedules = []
        Task { await load() }
    }

    // MARK: - Loading

    private static func initialDay() -> Date {
        let today = Date()
        let weekday = VulcanDate.calendar.component(.weekday, from: today)
        if weekday == 1 || weekday == 7 {
            return VulcanDate.startOfWeek(today)
        }
        return today
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            schedules = try await model.loadTimetable(weekStart: weekStart)
        } catch {
            self.error = AppModel.describe(error)
        }
        isLoading = false
    }
}
