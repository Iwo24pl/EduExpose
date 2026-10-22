import SwiftUI

struct DashboardView: View {
    var body: some View {
        TabView {
            Tab("Start", systemImage: "house.fill") {
                StartView()
            }

            Tab("Oceny", systemImage: "list.number") {
                GradesView()
            }

            Tab("Plan", systemImage: "calendar") {
                TimetableView()
            }

            Tab("Sprawdziany", systemImage: "checklist") {
                ExamsView()
            }

            Tab("Więcej", systemImage: "ellipsis.circle") {
                MoreView()
            }
        }
        .tint(Palette.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
