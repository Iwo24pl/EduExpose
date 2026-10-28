import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var login = ""
    @State private var password = ""
    @State private var entered = false
    @State private var glow = false
    @State private var orbit = false
    @AppStorage("login.registry") private var providerRaw = EduRegistry.eduVulcan.rawValue
    @FocusState private var focusedField: Field?

    private enum Field {
        case login
        case password
    }

    private var provider: EduRegistry {
        EduRegistry(rawValue: providerRaw) ?? .eduVulcan
    }

    private var providerBinding: Binding<EduRegistry> {
        Binding(
            get: { provider },
            set: { newValue in
                guard newValue != provider else { return }
                providerRaw = newValue.rawValue
                password = ""
                model.errorMessage = nil
                focusedField = .login
            }
        )
    }

    private var canSubmit: Bool {
        !model.isBusy
            && !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 22) {
                    header

                    if model.isAddingAccount {
                        addingAccountBar
                    }

                    form

                    if let message = model.errorMessage {
                        ErrorBanner(message: message)
                    }

                    footnote
                }
                .padding(22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear(perform: startEntrance)
    }

    /// A short, non-blocking intro: halo and logo first, then the copy and the
    /// form. Reduce Motion keeps the layout but drops every transition.
    private func startEntrance() {
        guard !entered else { return }
        entered = true
        glow = true
        if !reduceMotion {
            orbit = true
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            logoBadge

            VStack(spacing: 6) {
                Text("EduExpose")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.onSurface)

                Text("Dwa dzienniki. Jedna natywna aplikacja.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .offset(y: entered ? 0 : 14)
            .opacity(entered ? 1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.55).delay(0.2),
                value: entered
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var logoBadge: some View {
        ZStack {
            Color.clear
                .frame(width: 128, height: 128)
                .glassEffect(
                    .regular.tint(Palette.brandBlue.opacity(0.16)),
                    in: .circle
                )

            Circle()
                .trim(from: 0.04, to: 0.18)
                .stroke(
                    LinearGradient(
                        colors: [
                            Palette.brandBlueSoft.opacity(0),
                            Palette.brandBlueSoft,
                            Palette.brandBlueSoft.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 116, height: 116)
                .rotationEffect(.degrees(orbit ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 14).repeatForever(autoreverses: false),
                    value: orbit
                )

            BrandLogoView(size: 88)
        }
        .frame(width: 132, height: 132)
        .background {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Palette.brandBlue.opacity(0.38),
                            Palette.brandBlue.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 350, height: 350)
                .blur(radius: 44)
                .scaleEffect(glow ? 1.06 : 0.94)
                .opacity(entered ? 0.9 : 0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 7).repeatForever(autoreverses: true),
                    value: glow
                )
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.8),
                    value: entered
                )
                .allowsHitTesting(false)
        }
        .scaleEffect(entered ? 1 : 0.72)
        .opacity(entered ? 1 : 0)
        .blur(radius: entered ? 0 : 10)
        .animation(
            reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.76).delay(0.05),
            value: entered
        )
    }

    private var addingAccountBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Dodaj konto")
                .font(.headline)
                .foregroundStyle(Palette.onSurface)

            Spacer(minLength: 8)

            Button("Anuluj") {
                model.cancelAddAccount()
            }
            .font(.subheadline.weight(.semibold))
            .tint(Palette.primary)
        }
        .padding(.horizontal, 4)
    }

    private var form: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dziennik")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)

                    Picker("Dziennik", selection: providerBinding) {
                        ForEach(EduRegistry.allCases) { registry in
                            Text(registry.displayName).tag(registry)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isBusy)

                    Text(provider == .librus
                        ? "Zaloguj się kontem Konto LIBRUS (e-mail). Jedno konto rodzica może dodać kilkoro dzieci."
                        : "Zaloguj się loginem lub e-mailem eduVULCAN.")
                        .font(.caption2)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(provider.loginFieldLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)

                    TextField(provider.loginPlaceholder, text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(provider == .librus ? .emailAddress : .default)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .login)
                        .onSubmit {
                            focusedField = .password
                        }
                        .foregroundStyle(Palette.onSurface)
                        .padding(12)
                        .background(
                            Palette.secondaryContainer.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hasło")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)

                    SecureField("Hasło", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                        .foregroundStyle(Palette.onSurface)
                        .padding(12)
                        .background(
                            Palette.secondaryContainer.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }

                Button(action: submit) {
                    HStack(spacing: 10) {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(model.isBusy ? "Logowanie…" : "Zaloguj się")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.primary)
                .disabled(!canSubmit)
                .padding(.top, 4)
            }
        }
        .offset(y: entered ? 0 : 24)
        .opacity(entered ? 1 : 0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.9).delay(0.3),
            value: entered
        )
    }

    private var footnote: some View {
        Text("EduExpose nie jest oficjalną aplikacją VULCAN ani Librus. Dane logowania trafiają wyłącznie do wybranego dziennika, a sesja jest przechowywana w Keychain tego urządzenia.")
            .font(.footnote)
            .foregroundStyle(Palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .offset(y: entered ? 0 : 12)
            .opacity(entered ? 1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.42),
                value: entered
            )
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            await model.login(provider: provider, login: login, password: password)
        }
    }
}
