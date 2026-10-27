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
}

/// Called by the session actor after a successful login/refresh or after a
/// failure that invalidated the session. The caller stores the snapshot in
/// the Keychain and must not log it.
typealias LibrusSessionObserver = @Sendable (LibrusSession) async -> Void
