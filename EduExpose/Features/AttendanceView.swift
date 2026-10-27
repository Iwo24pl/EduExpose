import SwiftUI

struct AttendanceView: View {
    @Environment(AppModel.self) private var model

    @State private var snapshot: AttendanceSnapshot?
    @State private var period: Period?
    @State private var isLoading = false
    @State private var error: String?
    @State private var loadGeneration = 0

    private var periods: [Period] {
        model.activeAccount?.periods ?? []
    }

    var body: some View {
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
        .navigationTitle("Frekwencja")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: model.activeID) {
            await loadInitial()
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
        if let schoolYear = AttendanceLabels.schoolYear(in: item) {
            return "Rok szkolny \(schoolYear)"
        }
        if let number = item.number, number != 0 {
            return "Okres \(number)"
        }
        return "Okres"
    }

    // MARK: - Content

    private func content(_ snapshot: AttendanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.months.isEmpty,
               snapshot.subjects.isEmpty,
               snapshot.visibleEntries.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.clock",
                    title: "Brak danych o frekwencji",
                    message: "W tym okresie nie ma jeszcze wpisów."
                )
            } else {
                summary(snapshot)

                if !snapshot.months.isEmpty {
                    monthsSection(snapshot)
                }

                if !snapshot.subjects.isEmpty {
                    subjectsSection(snapshot)
                }

                if !snapshot.visibleEntries.isEmpty {
                    entriesSection(snapshot)
                }
            }
        }
    }

    // MARK: - Summary

    private func summary(_ snapshot: AttendanceSnapshot) -> some View {
        let totals = snapshot.totals
        let headline = snapshot.yearSummary ?? snapshot.latestMonth

        let title: String
        if snapshot.yearSummary != nil,
           let schoolYear = AttendanceLabels.schoolYear(in: snapshot.period) {
            title = "Rok szkolny \(schoolYear)"
        } else if let headline {
            title = AttendanceLabels.monthTitle(headline.month, in: snapshot.period)
        } else {
            title = "Frekwencja"
        }

        let subtitle: String
        if snapshot.yearSummary != nil {
            subtitle = "Frekwencja od początku roku"
        } else if headline != nil {
            subtitle = "Frekwencja w najnowszym miesiącu"
        } else {
            subtitle = "Brak statystyk miesięcznych"
        }

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    percentageRing(headline?.percentage)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Palette.onSurface)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(
                            "\(countLabel(totals.absences, one: "nieobecność", few: "nieobecności", many: "nieobecności")) · "
                                + countLabel(totals.lateArrivals, one: "spóźnienie", few: "spóźnienia", many: "spóźnień")
                        )
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    statTile(
                        "Nieobecności",
                        value: totals.absences,
                        detail: totals.unjustified > 0
                            ? "w tym \(countLabel(totals.unjustified, one: "nieusprawiedliwiona", few: "nieusprawiedliwione", many: "nieusprawiedliwionych"))"
                            : nil,
                        color: Palette.error
                    )
                    statTile(
                        "Spóźnienia",
                        value: totals.lateArrivals,
                        detail: totals.lateArrivalsJustified > 0
                            ? "w tym \(countLabel(totals.lateArrivalsJustified, one: "usprawiedliwione", few: "usprawiedliwione", many: "usprawiedliwionych"))"
                            : nil,
                        color: Palette.warning
                    )
                    statTile(
                        "Zwolnienia",
                        value: totals.exemptions,
                        detail: nil,
                        color: Palette.primary
                    )
                    statTile(
                        "Nieobecności szkolne",
                        value: totals.schoolAbsences,
                        detail: nil,
                        color: Palette.onSurfaceVariant
                    )
                }
            }
        }
    }

    private func percentageRing(_ percentage: Double?) -> some View {
        let value = AttendanceMath.normalizedPercentage(percentage ?? 0)

        return ZStack {
            Circle()
                .stroke(Palette.onSurfaceVariant.opacity(0.18), lineWidth: 8)

            Circle()
                .trim(from: 0, to: CGFloat(value / 100))
                .stroke(
                    attendanceColor(value),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(percentage == nil ? "—" : AttendanceMath.percentageText(value))
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.onSurface)
        }
        .frame(width: 92, height: 92)
    }

    private func statTile(
        _ title: String,
        value: Int,
        detail: String?,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.onSurface)
                .lineLimit(2)

            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .padding(12)
        .background(
            Palette.secondaryContainer.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Months

    private func monthsSection(_ snapshot: AttendanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Miesiące")

            GlassCard {
                VStack(spacing: 16) {
                    ForEach(snapshot.displayMonths) { month in
                        monthRow(
                            month,
                            period: snapshot.period,
                            totals: month.isYearSummary ? snapshot.totals : nil
                        )
                    }
                }
            }
        }
    }

    private func monthRow(
        _ month: PresenceMonthStats,
        period: Period,
        totals: AttendanceTotals? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(AttendanceLabels.monthTitle(month.month, in: period))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.onSurface)

                Spacer(minLength: 8)

                Text(AttendanceMath.percentageText(month.percentage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(attendanceColor(month.percentage))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.onSurfaceVariant.opacity(0.14))

                    Capsule()
                        .fill(attendanceColor(month.percentage))
                        .frame(width: proxy.size.width * CGFloat(month.percentage / 100))
                }
            }
            .frame(height: 6)

            Text(monthDetail(month, totals: totals))
                .font(.caption2)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
    }

    private func monthDetail(
        _ month: PresenceMonthStats,
        totals: AttendanceTotals? = nil
    ) -> String {
        let counts = totals ?? AttendanceTotals(month: month)
        var parts: [String] = []
        if counts.absences > 0 {
            parts.append(countLabel(counts.absences, one: "nieobecność", few: "nieobecności", many: "nieobecności"))
        }
        if counts.lateArrivals > 0 {
            parts.append(countLabel(counts.lateArrivals, one: "spóźnienie", few: "spóźnienia", many: "spóźnień"))
        }
        if counts.exemptions > 0 {
            parts.append(countLabel(counts.exemptions, one: "zwolnienie", few: "zwolnienia", many: "zwolnień"))
        }
        if counts.schoolAbsences > 0 {
            parts.append("\(counts.schoolAbsences) z powodu szkoły")
        }
        return parts.isEmpty ? "bez nieobecności" : parts.joined(separator: " · ")
    }

    // MARK: - Subjects

    private func subjectsSection(_ snapshot: AttendanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Przedmioty")

            GlassCard {
                VStack(spacing: 2) {
                    ForEach(snapshot.sortedSubjects) { subject in
                        subjectRow(subject)
                    }
                }
            }
        }
    }

    private func subjectRow(_ subject: PresenceSubjectStats) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(subject.subjectName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.onSurface)

                Text(subjectDetail(subject))
                    .font(.caption2)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(AttendanceMath.percentageText(subject.percentage))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(attendanceColor(subject.percentage))
        }
        .padding(.vertical, 8)
    }

    private func subjectDetail(_ subject: PresenceSubjectStats) -> String {
        var parts: [String] = []
        if subject.absences > 0 {
            parts.append(countLabel(subject.absences, one: "nieobecność", few: "nieobecności", many: "nieobecności"))
        }
        if subject.lateArrivals > 0 {
            parts.append(countLabel(subject.lateArrivals, one: "spóźnienie", few: "spóźnienia", many: "spóźnień"))
        }
        if subject.exemptions > 0 {
            parts.append(countLabel(subject.exemptions, one: "zwolnienie", few: "zwolnienia", many: "zwolnień"))
        }
        if subject.absencesDueToSchool > 0 {
            parts.append("\(subject.absencesDueToSchool) z powodu szkoły")
        }
        return parts.isEmpty ? "bez nieobecności" : parts.joined(separator: " · ")
    }

    // MARK: - Entries

    private func entriesSection(_ snapshot: AttendanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Nieobecności i spóźnienia")

            ForEach(snapshot.entryDays) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(VulcanDate.dayLabel(day.day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)

                    GlassCard {
                        VStack(spacing: 2) {
                            ForEach(day.entries) { entry in
                                entryRow(entry)
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: PresenceExtra) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(timeRange(entry.timeSlot))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.onSurface)

                if let category = entry.presenceType?.categoryName, !category.isEmpty {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }

            Spacer(minLength: 8)

            Text(entry.presenceType?.name ?? "Wpis frekwencji")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entryColor(entry))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(entryColor(entry).opacity(0.14), in: Capsule())
        }
        .padding(.vertical, 8)
    }

    private func timeRange(_ slot: Timeslot) -> String {
        let start = VulcanDate.time(slot.start)
        let end = VulcanDate.time(slot.end)
        if !start.isEmpty, !end.isEmpty {
            return "\(start)–\(end)"
        }
        if let display = slot.display, !display.isEmpty {
            return display
        }
        return "Lekcja \(slot.position)"
    }

    // MARK: - Loading

    private func loadInitial() async {
        period = model.activeAccount?.currentPeriod
        snapshot = nil

        guard period != nil else {
            isLoading = false
            error = "Konto nie ma aktywnego okresu."
            return
        }

        await load()
    }

    private func load() async {
        guard let period else {
            isLoading = false
            error = "Konto nie ma aktywnego okresu."
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil

        do {
            let loaded = try await model.loadAttendance(period: period)
            guard generation == loadGeneration else { return }
            snapshot = loaded
        } catch {
            guard generation == loadGeneration else { return }
            self.error = AppModel.describe(error)
        }

        if generation == loadGeneration {
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func attendanceColor(_ percentage: Double) -> Color {
        if percentage >= 95 {
            return Palette.success
        }
        if percentage >= 85 {
            return Palette.warning
        }
        return Palette.error
    }

    private func entryColor(_ entry: PresenceExtra) -> Color {
        guard let type = entry.presenceType else {
            return Palette.onSurfaceVariant
        }
        if type.late {
            return Palette.warning
        }
        if type.absenceJustified || type.legalAbsence {
            return Palette.success
        }
        if type.absence {
            return Palette.error
        }
        return Palette.primary
    }

    /// Polish plural forms: 1 nieobecność, 2–4 nieobecności, 5+ nieobecności.
    private func countLabel(_ count: Int, one: String, few: String, many: String) -> String {
        let lastDigit = count % 10
        let lastTwo = count % 100
        let noun: String
        if count == 1 {
            noun = one
        } else if (2...4).contains(lastDigit), !(12...14).contains(lastTwo) {
            noun = few
        } else {
            noun = many
        }
        return "\(count) \(noun)"
    }
}
