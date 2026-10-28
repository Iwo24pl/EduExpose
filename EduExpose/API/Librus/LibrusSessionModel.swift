import Foundation

/// The credentials used to recreate a Librus session after it expires.
///
/// `password` is optional because the backend can restore a cookie-only
/// session. When it is `nil` and the session dies, the actor raises
/// `LibrusError.reauthRequired` instead of asking the server again.
struct LibrusCredentials: Sendable, Equatable {
    var login: String
    var password: String?
}

/// How a Librus session was established. Web-cookie sessions refresh with
/// `/refreshToken`; portal-child sessions re-run the `AutoLoginToken` bridge.
enum LibrusAuthMethod: String, Codable, Sendable {
    case web
    case portal
}

/// Everything needed to recreate one child's Synergia session from a Konto
/// LIBRUS parent login. The child access token is short-lived; the portal
/// refresh token is the long-lived part.
struct LibrusPortalState: Codable, Sendable, Equatable {
    var email: String
    var password: String?
    var accountID: Int
    var accountLogin: String
    var portalAccessToken: String
    var portalRefreshToken: String?
    var portalExpiresAt: Date?
    var childAccessToken: String
    var childExpiresAt: Date?
}

/// A persisted Librus web session.
///
/// Only the cookies in `LibrusCookieJar.persistedNames` are stored. The
/// long-lived `DeviceCookie` keeps normal logins captcha-free; its
/// `Path=/OAuth` is preserved.
struct LibrusSession: Codable, Sendable, Equatable {
    var login: String
    var password: String?
    var cookies: [LibrusCookie]
    var loggedInAt: Date
    var loginCount: Int
    var lastRefreshAt: Date?
    var lastRefreshFailedAt: Date?
    var authMethod: LibrusAuthMethod? = nil
    var portal: LibrusPortalState? = nil

    var method: LibrusAuthMethod {
        authMethod ?? (portal == nil ? .web : .portal)
    }
}

/// Called by the session actor after a successful login/refresh or after a
/// failure that invalidated the session. The caller stores the snapshot in
/// the Keychain and must not log it.
typealias LibrusSessionObserver = @Sendable (LibrusSession) async -> Void
