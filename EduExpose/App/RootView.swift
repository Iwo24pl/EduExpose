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
        .preferredColorScheme(.dark)
        .tint(Palette.primary)
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
                BrandLogoView(size: 88)
                ProgressView()
                    .tint(Palette.primary)
                Text("EduExpose")
                    .font(.headline)
                    .foregroundStyle(Palette.onSurface)
            }
        }
    }
}

struct BrandLogoView: View {
    let size: CGFloat

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: Palette.brandBlue.opacity(0.35), radius: size * 0.22)
            .accessibilityLabel("Logo EduExpose")
    }
}

#Preview {
    RootView()
}
