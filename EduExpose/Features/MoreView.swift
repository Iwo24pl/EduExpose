import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    SectionTitle(title: "Nauka")

                    GlassCard {
                        VStack(spacing: 14) {
                            NavigationLink {
                                AttendanceView()
                            } label: {
                                MoreRow(
                                    icon: "calendar.badge.clock",
                                    title: "Frekwencja",
                                    subtitle: "Obecności, spóźnienia i zwolnienia"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.5)

                            NavigationLink {
                                HomeworkView()
                            } label: {
                                MoreRow(
                                    icon: "book.closed",
                                    title: "Zadania domowe",
                                    subtitle: "Prace domowe i terminy"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.5)

                            NavigationLink {
                                NotesView()
                            } label: {
                                MoreRow(
                                    icon: "note.text",
                                    title: "Notatki",
                                    subtitle: "Uwagi i punkty"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.5)

                            NavigationLink {
                                AnnouncementsView()
                            } label: {
                                MoreRow(
                                    icon: "megaphone",
                                    title: "Ogłoszenia",
                                    subtitle: "Komunikaty szkoły"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.5)

                            NavigationLink {
                                MessagesView()
                            } label: {
                                MoreRow(
                                    icon: "envelope",
                                    title: "Wiadomości",
                                    subtitle: "Skrzynka wiadomości"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SectionTitle(title: "Aplikacja")

                    GlassCard {
                        Button {
                            showSettings = true
                        } label: {
                            MoreRow(
                                icon: "gearshape",
                                title: "Ustawienia",
                                subtitle: "Konto, uczniowie i aktualizacje"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("EduExpose \(version)")
                        .font(.caption)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Więcej")
            .dashboardChrome()
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
            }
        }
    }

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                if let account = model.activeAccount {
                    Text(account.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)

                    Text(account.schoolName)
                        .font(.subheadline)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)

                    if let classLabel = account.classLabel {
                        InfoPill(text: classLabel, icon: "person.3")
                    }
                } else {
                    Text("Brak aktywnego ucznia")
                        .font(.headline)
                        .foregroundStyle(Palette.onSurface)

                    Text("Dodaj konto w ustawieniach, aby zobaczyć dane szkoły.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.onPrimaryContainer)
                .frame(width: 38, height: 38)
                .background(
                    Palette.primaryContainer,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onSurface)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.onSurfaceVariant)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .contentShape(Rectangle())
    }
}
