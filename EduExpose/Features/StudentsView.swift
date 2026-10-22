import SwiftUI

struct StudentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let message = model.errorMessage {
                        ErrorBanner(message: message)
                    }

                    if model.pending.isEmpty {
                        EmptyStateView(
                            icon: "person.2",
                            title: "Brak uczniów do wyboru",
                            message: "Zaloguj się ponownie, aby pobrać listę kont."
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(model.pending) { student in
                                studentRow(student)
                            }
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wybierz uczniów")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.onSurface)

            Text("Zaznacz konta, które chcesz dodać do aplikacji.")
                .font(.subheadline)
                .foregroundStyle(Palette.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    private func studentRow(_ student: StoredStudent) -> some View {
        let isSelected = model.selected.contains(student.id)

        return Button {
            if isSelected {
                model.selected.remove(student.id)
            } else {
                model.selected.insert(student.id)
            }
        } label: {
            GlassCard {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(student.account.displayName)
                            .font(.headline)
                            .foregroundStyle(Palette.onSurface)

                        Text(student.account.schoolName)
                            .font(.subheadline)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        if let classLabel = student.account.classLabel {
                            InfoPill(text: classLabel, icon: "person.3")
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Palette.primary : Palette.outline)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isSelected ? "Wybrano" : "Nie wybrano")
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                model.confirmSelection()
            } label: {
                Text("Kontynuuj (\(model.selected.count))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.primary)
            .disabled(model.selected.isEmpty)

            if model.isAddingAccount {
                Button("Anuluj") {
                    model.cancelAddAccount()
                }
                .font(.subheadline.weight(.semibold))
                .tint(Palette.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
}
