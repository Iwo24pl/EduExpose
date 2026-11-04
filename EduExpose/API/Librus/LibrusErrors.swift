import Foundation

/// Typed Librus failures. The UI maps these to Polish messages; nothing
/// here contains credentials, cookies or response bodies.
enum LibrusError: LocalizedError, Sendable, Equatable {
    case invalidCredentials
    case captchaRequired
    case actionRequired
    case sessionExpired(status: Int)
    case reauthRequired
    case insufficientScopes(endpoint: String)
    case moduleUnavailable(endpoint: String, status: Int)
    case maintenance
    case rateLimited
    case retryLater(status: Int)
    case unsafeURL
    case unsafeRedirect
    case unexpectedResponse
    case httpStatus(Int)
    case decoding(endpoint: String)
    case network
    case missingSession
    case readOnly

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Nieprawidłowy e-mail lub hasło do Librusa."
        case .captchaRequired:
            return "Librus wymaga dodatkowej weryfikacji. Zaloguj się ponownie w przeglądarce Librusa i spróbuj później."
        case .actionRequired:
            return "Konto Librus wymaga działania na stronie Librusa (np. zmiany hasła lub akceptacji regulaminu)."
        case .sessionExpired:
            return "Sesja Librus wygasła. Zaloguj się ponownie."
        case .reauthRequired:
            return "Sesja Librus wygasła, a zapisane dane nie pozwalają jej odnowić. Zaloguj się ponownie."
        case .insufficientScopes:
            return "Ta sekcja nie jest dostępna dla tego konta Librus."
        case .moduleUnavailable:
            return "Ta sekcja nie jest dostępna dla tego konta Librus."
        case .maintenance:
            return "Librus jest chwilowo niedostępny. Spróbuj ponownie później."
        case .rateLimited:
            return "Librus ograniczył liczbę żądań. Odczekaj chwilę i spróbuj ponownie."
        case .retryLater:
            return "Librus jest chwilowo niedostępny. Spróbuj ponownie później."
        case .unsafeURL, .unsafeRedirect:
            return "Librus zwrócił niebezpieczny adres. Przerwano połączenie."
        case .unexpectedResponse:
            return "Librus zwrócił nieoczekiwaną odpowiedź."
        case .httpStatus(let status):
            return "Librus zwrócił błąd \(status)."
        case .decoding:
            return "Nie udało się odczytać danych z Librusa."
        case .network:
            return "Brak połączenia z Librusem. Sprawdź internet i spróbuj ponownie."
        case .missingSession:
            return "Nie udało się utworzyć sesji Librus."
        case .readOnly:
            return "Ta operacja nie jest dostępna dla Librusa w tej wersji."
        }
    }

    /// A short, non-sensitive code for the diagnostics trace.
    var traceCode: String {
        switch self {
        case .invalidCredentials: return "invalid_credentials"
        case .captchaRequired: return "captcha"
        case .actionRequired: return "action_required"
        case .sessionExpired: return "session_expired"
        case .reauthRequired: return "reauth_required"
        case .insufficientScopes: return "insufficient_scopes"
        case .moduleUnavailable: return "module_unavailable"
        case .maintenance: return "maintenance"
        case .rateLimited: return "rate_limited"
        case .retryLater: return "retry_later"
        case .unsafeURL: return "unsafe_url"
        case .unsafeRedirect: return "unsafe_redirect"
        case .unexpectedResponse: return "unexpected_response"
        case .httpStatus: return "http_status"
        case .decoding: return "decoding"
        case .network: return "network"
        case .missingSession: return "missing_session"
        case .readOnly: return "read_only"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .maintenance, .rateLimited, .retryLater, .network:
            return true
        default:
            return false
        }
    }
}
