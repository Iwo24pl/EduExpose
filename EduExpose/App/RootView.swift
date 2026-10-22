import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView()
            case .login:
                LoginView()
            case .students:
                StudentsView()
            case .dashboard:
                DashboardView()
            }
        }
        .environment(model)
        .task {
            await model.bootstrap()
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 18) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Palette.primary)
                    .glassEffect(.regular, in: .circle)
                    .frame(width: 88, height: 88)
                ProgressView()
                    .tint(Palette.primary)
                Text("EduExpose")
                    .font(.headline)
                    .foregroundStyle(Palette.onSurface)
            }
        }
    }
}

#Preview {
    RootView()
}
