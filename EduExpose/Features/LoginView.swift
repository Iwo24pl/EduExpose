import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var login = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case login
        case password
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
    }

    private var header: some View {
        VStack(spacing: 16) {
            BrandLogoView(size: 84)

            VStack(spacing: 6) {
                Text("EduExpose")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.onSurface)

                Text("Dziennik eduVULCAN w natywnej formie.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Login")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)

                    TextField("Login", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
    }

    private var footnote: some View {
        Text("EduExpose nie jest oficjalną aplikacją VULCAN. Dane logowania trafiają wyłącznie do eduVULCAN, a sesja jest przechowywana w Keychain tego urządzenia.")
            .font(.footnote)
            .foregroundStyle(Palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            await model.login(login: login, password: password)
        }
    }
}
