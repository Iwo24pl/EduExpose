import SwiftUI

struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(Palette.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    var icon: String = "tray"
    let title: String
    var message: String = ""

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Palette.primary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.onSurface)
                if !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.error)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.error.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(Palette.error)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                if let retry {
                    Button("Spróbuj ponownie", action: retry)
                        .buttonStyle(.glass)
                        .tint(Palette.primary)
                }
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.primary)
            Text("Ładowanie…")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct InfoPill: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Palette.onSurfaceVariant)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Palette.secondaryContainer, in: Capsule())
    }
}

struct ProviderBadge: View {
    let provider: EduRegistry

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: provider == .librus ? "books.vertical" : "graduationcap")
            Text(provider.displayName)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(provider == .librus ? Palette.success : Palette.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (provider == .librus ? Palette.success : Palette.primary).opacity(0.14),
            in: Capsule()
        )
        .accessibilityLabel("Dziennik \(provider.displayName)")
    }
}

struct GradeBadge: View {
    let text: String
    let value: Double?

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.grade(value))
            .frame(minWidth: 38, minHeight: 30)
            .padding(.horizontal, 5)
            .background(
                Color.grade(value).opacity(0.14),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

struct StudentMenuButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.students) { student in
                Button {
                    model.selectStudent(student.id)
                } label: {
                    if student.id == model.activeID {
                        Label(student.account.displayName, systemImage: "checkmark")
                    } else {
                        Text(student.account.displayName)
                    }
                }
            }
            Divider()
            Button {
                model.beginAddAccount()
            } label: {
                Label("Dodaj konto", systemImage: "person.badge.plus")
            }
            Button(role: .destructive) {
                model.logout()
            } label: {
                Label("Wyloguj", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.primaryContainer)
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.onPrimaryContainer)
            }
            .frame(width: 30, height: 30)
            .accessibilityLabel("Przełącz ucznia")
        }
    }

    private var initials: String {
        let first = model.activeAccount?.pupil.firstName.first.map(String.init) ?? "?"
        let last = model.activeAccount?.pupil.surname.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

struct SettingsButton: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.medium))
        }
        .tint(Palette.onSurface)
        .accessibilityLabel("Ustawienia")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

extension View {
    func dashboardChrome() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                StudentMenuButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton()
            }
        }
    }
}

extension Color {
    static func grade(_ value: Double?) -> Color {
        guard let value else { return Palette.onSurfaceVariant }
        if value >= 4.75 { return Palette.success }
        if value >= 3.5 { return Palette.primary }
        if value >= 2.75 { return Palette.warning }
        return Palette.error
    }
}
