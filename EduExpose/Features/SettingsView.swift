import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var isCheckingUpdate = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        accountSection

                        if let message = model.errorMessage {
                            ErrorBanner(message: message)
                        }

                        studentSection
                        addAccountButton
                        updateSection
                        sessionSection
                        aboutSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Konto")

            if let account = model.activeAccount {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(account.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.onSurface)

                        Text(account.schoolName)
                            .font(.subheadline)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            if let classLabel = account.classLabel {
                                InfoPill(text: classLabel, icon: "person.3")
                            }

                            if let period = account.currentPeriod {
                                InfoPill(text: periodTitle(period), icon: "calendar")
                            }
                        }

                        if let period = account.currentPeriod {
                            Text("\(VulcanDate.dayLabel(period.startAt)) – \(VulcanDate.dayLabel(period.endAt))")
                                .font(.footnote)
                                .foregroundStyle(Palette.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Brak aktywnego konta",
                    message: "Dodaj konto ucznia, aby zobaczyć szczegóły."
                )
            }
        }
    }

    private func periodTitle(_ period: Period) -> String {
        if let number = period.number {
            return "Okres \(number)"
        }
        return "Okres"
    }

    // MARK: Students

    private var studentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Uczniowie")

            if model.students.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "Brak uczniów",
                    message: "Dodaj konto, aby rozpocząć."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(model.students) { student in
                        studentRow(student)
                    }
                }
            }
        }
    }

    private func studentRow(_ student: StoredStudent) -> some View {
        GlassCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.account.displayName)
                        .font(.headline)
                        .foregroundStyle(Palette.onSurface)

                    Text(student.account.schoolName)
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    model.setEnabled(!student.isEnabled, for: student.id)
                } label: {
                    Image(systemName: student.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(student.isEnabled ? Palette.primary : Palette.outline)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(student.isEnabled ? "Wyłącz konto" : "Włącz konto")

                Button(role: .destructive) {
                    model.removeStudent(student.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(Palette.error)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Usuń konto")
            }
        }
    }

    private var addAccountButton: some View {
        Button {
            dismiss()
            model.beginAddAccount()
        } label: {
            Label("Dodaj konto", systemImage: "person.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(Palette.primary)
    }

    // MARK: Updates

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Aktualizacje")

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sprawdź, czy w GitHub Releases jest nowsza wersja aplikacji.")
                        .font(.footnote)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task {
                            isCheckingUpdate = true
                            await model.checkForUpdate()
                            isCheckingUpdate = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isCheckingUpdate {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text("Sprawdź aktualizacje")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(Palette.primary)
                    .disabled(isCheckingUpdate)

                    if let info = model.updateInfo {
                        Divider()

                        HStack(spacing: 8) {
                            Text(info.version)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.onSurface)

                            Spacer(minLength: 8)

                            if info.isNewer {
                                InfoPill(text: "Nowa wersja", icon: "arrow.down.circle")
                            }
                        }

                        if info.isNewer {
                            Text("Dostępna jest nowsza wersja.")
                                .font(.footnote)
                                .foregroundStyle(Palette.success)
                        }

                        Link("Otwórz GitHub Releases", destination: info.url)
                            .font(.footnote.weight(.semibold))
                            .tint(Palette.primary)
                    }
                }
            }
        }
    }

    // MARK: Session and about

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Sesja")

            Button(role: .destructive) {
                model.logout()
                dismiss()
            } label: {
                Label("Wyloguj się", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(Palette.error)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "O aplikacji")

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("EduExpose \(version)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)

                    Text("Nieoficjalny klient eduVULCAN. Nie jest powiązany z VULCAN.")
                        .font(.footnote)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("github.com/Iwo24pl/EduExpose", destination: URL(string: "https://github.com/Iwo24pl/EduExpose")!)
                        .font(.footnote.weight(.semibold))
                        .tint(Palette.primary)
                }
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
