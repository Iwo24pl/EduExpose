import Foundation

/// Protocol constants for the current Librus web-cookie flow.
///
/// The implementation is based on the public protocol notes of
/// `librus-synergia` (MIT) and `emsi/librus_pyapi` (AGPL — protocol facts
/// only, no code copied). `client_id=46` is a public OAuth client id, not a
/// secret. Do not add the old mobile password-grant client here: that flow
/// has been dead since around March 2026.
enum LibrusConstants {
    static let clientID = "46"

    static let portalLoginURL = URL(string: "https://synergia.librus.pl/loguj/portalRodzina")!
    static let authorizationURL = URL(string: "https://api.librus.pl/OAuth/Authorization?client_id=46")!
    static let authorizationScopeURL = URL(
        string: "https://api.librus.pl/OAuth/Authorization?client_id=46&response_type=code&scope=mydata"
    )!
    static let refreshURL = URL(string: "https://synergia.librus.pl/refreshToken")!
    static let messagesBootstrapURL = URL(string: "https://synergia.librus.pl/wiadomosci3")!
    static let gatewayBase = URL(string: "https://synergia.librus.pl/gateway/api/2.0/")!
    static let messagesBase = URL(string: "https://wiadomosci.librus.pl/api/")!
    static let portalAuthorizeURL = URL(string: "https://portal.librus.pl/konto-librus/redirect/dru")!
    static let portalLoginURL = URL(string: "https://portal.librus.pl/konto-librus/login/action")!
    static let portalTokenURL = URL(string: "https://portal.librus.pl/oauth2/access_token")!
    static let portalAccountsURL = URL(string: "https://portal.librus.pl/api/v3/SynergiaAccounts")!
    static let portalFreshBase = URL(string: "https://portal.librus.pl/api/v3/SynergiaAccounts/fresh/")!
    static let autoLoginTokenURL = URL(string: "https://api.librus.pl/2.0/AutoLoginToken")!
    static let portalClientID = "VaItV6oRutdo8fnjJwysnTjVlvaswf52ZqmXsJGP"
    static let portalRedirectURI = "app://librus"
    static let portalRequestedWith = "pl.librus.synergiaDru2"

    static let oauthTokenCookie = "oauth_token"
    static let deviceCookie = "DeviceCookie"

    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
    static let acceptLanguage = "pl-PL,pl;q=0.9,en;q=0.8"

    static let loginHeaders: [String: String] = [
        "Accept": "*/*",
        "Accept-Language": acceptLanguage,
        "Cache-Control": "no-cache",
        "Origin": "https://api.librus.pl",
        "Pragma": "no-cache",
        "Referer": "https://api.librus.pl/OAuth/Authorization?client_id=46",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
        "User-Agent": userAgent,
        "X-Requested-With": "XMLHttpRequest"
    ]

    static let maxOAuthRedirects = 10
    static let requestTimeout: TimeInterval = 30
    static let resourceTimeout: TimeInterval = 60
    static let maximumBodyBytes = 8 * 1024 * 1024

    // The references assume a ~20 h session even though some cookies live
    // longer; refreshing early is cheaper than a captcha challenge.
    static let sessionLifetime: TimeInterval = 20 * 60 * 60
    static let sessionSafetyMargin: TimeInterval = 5 * 60
    static let sessionRefreshAfter: TimeInterval = 2 * 60 * 60
    // A Synergia session established through AutoLoginToken is a normal web
    // session, not a 20-hour mobile OAuth session.
    static let portalSessionLifetime: TimeInterval = 45 * 60
    static let portalSessionRefreshAfter: TimeInterval = 30 * 60
    static let childTokenLifetime: TimeInterval = 6 * 60 * 60
    static let portalLoginBackoff: TimeInterval = 60
    static let refreshBackoff: TimeInterval = 30 * 60
    static let loginBackoff: TimeInterval = 60

    static let messagesDenialBackoff: TimeInterval = 5 * 60
    static let messagesReloginBackoff: TimeInterval = 10 * 60
    static let referenceDataLifetime: TimeInterval = 24 * 60 * 60
    static let userDataSourceLifetime: TimeInterval = 60
}
