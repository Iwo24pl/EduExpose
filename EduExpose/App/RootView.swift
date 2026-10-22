import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Start", systemImage: "house") {
                PlaceholderScreen(
                    title: "Start",
                    message: "Tutaj pojawi się numer szczęścia, ostatnie oceny i najbliższe sprawdziany."
                )
            }

            Tab("Oceny", systemImage: "list.number") {
                PlaceholderScreen(
                    title: "Oceny",
                    message: "Przegląd ocen, średnich i podsumowań okresowych."
                )
            }

            Tab("Plan", systemImage: "calendar") {
                PlaceholderScreen(
                    title: "Plan",
                    message: "Tygodniowy plan lekcji wraz z zastępstwami."
                )
            }

            Tab("Sprawdziany", systemImage: "checklist") {
                PlaceholderScreen(
                    title: "Sprawdziany",
                    message: "Sprawdziany, kartkówki i zadania domowe."
                )
            }

            Tab("Więcej", systemImage: "ellipsis.circle") {
                PlaceholderScreen(
                    title: "Więcej",
                    message: "Notatki, ogłoszenia, wiadomości i zarządzanie kontem."
                )
            }
        }
        .tint(Palette.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EduExpose")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.primary)
                                .textCase(.uppercase)
                                .tracking(1.2)

                            Text(message)
                                .font(.body)
                                .foregroundStyle(Palette.onSurface)
                        }
                    }

                    Text("Szkielet M0 · ekrany w budowie")
                        .font(.footnote)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
                .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
}
