import Foundation
import CryptoKit
import os

enum LoginError: LocalizedError {
    case csrf
    case captcha
    case invalidCredentials
    case emailNotConfirmed
    case api(String)
    case noAccounts

    var errorDescription: String? {
        switch self {
        case .csrf: return "Nie udało się odczytać tokenu logowania. Spróbuj ponownie."
        case .captcha: return "Weryfikacja captchy nie powiodła się. Spróbuj ponownie."
        case .invalidCredentials: return "Nieprawidłowy login lub hasło."
        case .emailNotConfirmed: return "Twój adres e-mail nie został jeszcze potwierdzony."
        case .api(let message): return message
        case .noAccounts: return "Nie znaleziono kont uczniów dla tego loginu."
        }
    }
}

struct ApiApResponse: Decodable {
    let success: Bool
    let tokens: [String]
    let accessToken: String
    let isConsentAccepted: Bool
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case tokens = "Tokens"
        case accessToken = "AccessToken"
        case isConsentAccepted = "IsConsentAccepted"
        case errorMessage = "ErrorMessage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        tokens = (try? container.decode([String].self, forKey: .tokens)) ?? []
        accessToken = (try? container.decode(String.self, forKey: .accessToken)) ?? ""
        isConsentAccepted = (try? container.decode(Bool.self, forKey: .isConsentAccepted)) ?? true
        errorMessage = try? container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

struct JwtPayload: Decodable {
    let tenant: String
}

/// Parsing helpers for the eduVULCAN web login page.
enum LoginPage {
    struct Captcha {
        let challenge: String
        let difficulty: UInt32
        let rounds: Int
    }

    /// Reads the anti-forgery token from the hidden input rendered by ASP.NET.
    static func csrfToken(in html: String) -> String? {
        let pattern = #"<input[^>]*\bname\s*=\s*(?:"__RequestVerificationToken"|'__RequestVerificationToken'|__RequestVerificationToken\b)[^>]*>"#
        guard let tag = firstMatch(html, pattern)?.first else { return nil }
        return attribute(tag, "value")
    }

    /// Reads the proof-of-work captcha challenge from `div.captcha-wrapper`.
    static func captcha(in html: String) -> Captcha? {
        let pattern = #"<div[^>]*\bclass\s*=\s*"[^"]*captcha-wrapper[^"]*"[^>]*>"#
        guard let tag = firstMatch(html, pattern)?.first,
              let challenge = attribute(tag, "data-challenge"),
              let difficulty = attribute(tag, "data-difficulty").flatMap(UInt32.init),
              let rounds = attribute(tag, "data-rounds").flatMap(Int.init) else {
            return nil
        }
        return Captcha(challenge: challenge, difficulty: difficulty, rounds: rounds)
    }

    /// Reads `data.ShowCaptcha` from `POST /Account/QueryUserInfo`.
    /// Returns `nil` when the payload is not the expected object.
    static func showCaptcha(in data: Data) -> Bool? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any],
              let payload = object["data"] as? [String: Any] else {
            return nil
        }
        if let flag = payload["ShowCaptcha"] as? Bool { return flag }
        if let text = payload["ShowCaptcha"] as? String {
            return text.caseInsensitiveCompare("true") == .orderedSame
        }
        return nil
    }

    /// The portal re-renders the login form when the captcha answer is missing or too slow.
    static func isCaptchaRejection(_ html: String) -> Bool {
        let normalized = html.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return normalized.contains("poczekaj przed przejsciem dalej")
    }

    static func firstMatch(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) else {
            return nil
        }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : nsText.substring(with: range))
        }
        return groups
    }

    static func attribute(_ tag: String, _ name: String) -> String? {
        let pattern = #"(?:\s|<)"#
            + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let groups = firstMatch(tag, pattern), groups.count > 2 else { return nil }
        return groups[1].isEmpty ? groups[2] : groups[1]
    }
}

/// A fresh portal session, including the URL the browser would follow after
/// the login POST. That redirect is what establishes the mailbox SSO session.
struct PortalSession: Sendable {
    let cookies: [CookieSnapshot]
    let postLoginURL: URL?
}

/// Signs in through the eduVULCAN web portal and registers Hebe CE devices.
struct PrometheusLoginService {
    let session: URLSession
    private let base = "https://eduvulcan.pl"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
    private let acceptLanguage = "pl-PL,pl;q=0.9,en;q=0.8"
    private let acceptHTML = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    private let logger = Logger(subsystem: "com.iwo24pl.eduexpose", category: "login")

    init(session: URLSession) {
        self.session = session
    }

    func signIn(login: String, password: String) async throws -> [StoredStudent] {
        let authentication = try await authenticate(login: login, password: password)
        let apiAp = authentication.response

        guard apiAp.success else {
            throw LoginError.api(apiAp.errorMessage ?? "API /api/ap zwróciło błąd.")
        }
        guard !apiAp.tokens.isEmpty else {
            throw LoginError.noAccounts
        }

        var grouped: [String: [String]] = [:]
        for token in apiAp.tokens {
            let tenant = (try? decodeJWT(token).tenant) ?? "eduvulcan"
            grouped[tenant, default: []].append(token)
        }

        var result: [StoredStudent] = []
        for (tenant, tokens) in grouped {
            var credential = try Signing.makeCredential()
            let client = HebeClient(credential: credential, session: session)
            credential = try await client.registerJWT(tokens: tokens, tenant: tenant)
            let accounts = try await client.accounts()
            for account in accounts {
                result.append(StoredStudent(
                    id: account.id,
                    account: account,
                    credential: credential,
                    restUrl: HebeClient.dataEndpoint(
                        for: account,
                        fallback: credential.restUrl ?? ""
                    ),
                    login: login,
                    password: password,
                    tenant: tenant,
                    isEnabled: true
                ))
            }
        }

        guard !result.isEmpty else {
            throw LoginError.noAccounts
        }
        return result.sorted { $0.account.displayName < $1.account.displayName }
    }

    /// Re-authenticates against the portal without registering a Hebe device.
    /// Pass the exact login URL reached by the mailbox redirect chain: it
    /// carries the `ReturnUrl` that establishes the mailbox SSO session.
    func portalCookies(
        login: String,
        password: String,
        loginURL: URL? = nil
    ) async throws -> PortalSession {
        let result = try await authenticate(
            login: login,
            password: password,
            portalLoginURL: loginURL
        )
        guard result.response.success else {
            throw LoginError.api(result.response.errorMessage ?? "API /api/ap zwróciło błąd.")
        }
        let storage = session.configuration.httpCookieStorage ?? .shared
        return PortalSession(
            cookies: CookieSnapshot.capturePortal(storage.cookies ?? []),
            postLoginURL: result.postLoginURL
        )
    }

    private func authenticate(
        login: String,
        password: String,
        portalLoginURL: URL? = nil
    ) async throws -> (response: ApiApResponse, postLoginURL: URL?) {
        let loginURL = try portalLoginURL ?? makeLoginURL(returnPath: nil)
        let showCaptcha = await queryUserInfo(login)
        let html = try await loginPage(url: loginURL)
        await MailTraceStore.shared.record(
            "login.page",
            "\(MailTraceRedaction.safeURL(loginURL)) csrf=\(LoginPage.csrfToken(in: html) != nil)"
        )
        if html.contains("Twój adres e-mail nie został jeszcze potwierdzony.") {
            throw LoginError.emailNotConfirmed
        }

        guard let csrf = LoginPage.csrfToken(in: html) else {
            throw LoginError.csrf
        }

        var captcha = ""
        let challenge = LoginPage.captcha(in: html)
        if showCaptcha ?? (challenge != nil) {
            guard let challenge else {
                throw LoginError.captcha
            }
            captcha = captchaResponse(
                challenge: challenge.challenge,
                difficulty: challenge.difficulty,
                rounds: challenge.rounds
            )
        }

        let postLoginURL = try await postLogin(
            login: login,
            password: password,
            csrf: csrf,
            captcha: captcha,
            at: loginURL
        )
        // A browser follows Location immediately. This is what completes the
        // authenticated return chain (and, for the mailbox, the SSO handshake).
        if let postLoginURL {
            await MailTraceStore.shared.record(
                "login.location",
                MailTraceRedaction.safeURL(postLoginURL)
            )
            var follow = URLRequest(url: postLoginURL)
            follow.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            follow.setValue(acceptHTML, forHTTPHeaderField: "Accept")
            follow.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
            follow.setValue(loginURL.absoluteString, forHTTPHeaderField: "Referer")
            if let (_, response) = try? await session.data(for: follow) {
                let finalURL = (response as? HTTPURLResponse)?.url
                await MailTraceStore.shared.record(
                    "login.follow",
                    finalURL.map(MailTraceRedaction.safeURL) ?? "-"
                )
            } else {
                await MailTraceStore.shared.record("login.follow", "failed")
            }
        }
        let apiAp = try await apiApWithConsent()
        return (apiAp, postLoginURL)
    }

    private func makeLoginURL(returnPath: String?) throws -> URL {
        guard var components = URLComponents(string: base + "/logowanie") else {
            throw LoginError.api("Nieprawidłowy adres logowania.")
        }
        if let returnPath, !returnPath.isEmpty {
            components.queryItems = [URLQueryItem(name: "ReturnUrl", value: returnPath)]
        }
        guard let url = components.url else {
            throw LoginError.api("Nieprawidłowy adres logowania.")
        }
        return url
    }

    // MARK: Portal steps

    /// Returns `nil` when the portal could not be asked, so the caller can fall back
    /// to the captcha element rendered on the login page.
    private func queryUserInfo(_ login: String) async -> Bool? {
        guard let url = URL(string: base + "/Account/QueryUserInfo") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        // The portal expects `alias`; `UserName` is the form field and returns a bare boolean.
        request.httpBody = formBody([("alias", login)])
        guard let (data, response) = try? await session.data(for: request) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            logger.warning("QueryUserInfo zwróciło HTTP \(http.statusCode)")
            return nil
        }
        let parsed = LoginPage.showCaptcha(in: data)
        let description = parsed.map { $0 ? "true" : "false" } ?? "brak danych"
        logger.debug("QueryUserInfo: ShowCaptcha=\(description)")
        return parsed
    }

    /// Fetches the login page with a clean portal session, retrying once when the form is missing.
    private func loginPage(url: URL) async throws -> String {
        clearPortalCookies()
        var lastError: Error?
        var sawPage = false

        for attempt in 0..<2 {
            if attempt > 0 {
                clearPortalCookies()
                await visitHomePage()
            }
            do {
                let (html, response) = try await fetchLoginPage(url)
                lastError = nil
                sawPage = true
                if LoginPage.csrfToken(in: html) != nil
                    || html.contains("Twój adres e-mail nie został jeszcze potwierdzony.") {
                    return html
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let url = response.url?.absoluteString ?? "-"
                logger.warning("Strona logowania bez tokenu CSRF: HTTP \(status), \(url, privacy: .public), \(html.count) znaków")
            } catch {
                lastError = error
                logger.error("Nie udało się pobrać strony logowania: \(String(describing: error), privacy: .public)")
            }
        }

        if let lastError, !sawPage {
            throw lastError
        }
        throw LoginError.csrf
    }

    private func fetchLoginPage(_ url: URL) async throws -> (String, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptHTML, forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        return (String(decoding: data, as: UTF8.self), response)
    }

    private func visitHomePage() async {
        guard let url = URL(string: base + "/") else { return }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptHTML, forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        _ = try? await session.data(for: request)
    }

    private func postLogin(
        login: String,
        password: String,
        csrf: String,
        captcha: String,
        at url: URL
    ) async throws -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptHTML, forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(base, forHTTPHeaderField: "Origin")
        request.httpBody = formBody([
            ("UserName", login),
            ("Password", password),
            ("captcha-response", captcha),
            ("__RequestVerificationToken", csrf)
        ])

        let (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        let body = String(decoding: data, as: UTF8.self)

        if body.contains("Twój adres e-mail nie został jeszcze potwierdzony.") {
            throw LoginError.emailNotConfirmed
        }
        guard let http = response as? HTTPURLResponse else {
            throw LoginError.api("Serwer nie odpowiedział.")
        }
        if http.statusCode >= 500 {
            throw LoginError.api("Serwer logowania zwrócił błąd \(http.statusCode). Spróbuj ponownie.")
        }
        if let location = http.value(forHTTPHeaderField: "Location"),
           let next = URL(string: location, relativeTo: url)?.absoluteURL {
            return next
        }
        if LoginPage.isCaptchaRejection(body) {
            throw LoginError.captcha
        }
        throw LoginError.invalidCredentials
    }

    private func apiApWithConsent() async throws -> ApiApResponse {
        let initial = try await apiAp(accessToken: nil)
        if initial.isConsentAccepted {
            return initial
        }
        try await acceptConsent(accessToken: initial.accessToken.isEmpty ? nil : initial.accessToken)
        let refreshed = try await apiAp(accessToken: initial.accessToken.isEmpty ? nil : initial.accessToken)
        guard refreshed.isConsentAccepted else {
            throw LoginError.api(refreshed.errorMessage ?? "Nie udało się zaakceptować regulaminu.")
        }
        return refreshed
    }

    private func apiAp(accessToken: String?) async throws -> ApiApResponse {
        guard let url = URL(string: base + "/api/ap") else {
            throw LoginError.api("Nieprawidłowy adres API.")
        }
        var request = URLRequest(url: url)
        request.setValue("Dart/3.11 (dart:io)", forHTTPHeaderField: "user-agent")
        request.setValue("1", forHTTPHeaderField: "vapi")
        request.setValue("api%2fap", forHTTPHeaderField: "vcanonicalurl")
        request.setValue("Android", forHTTPHeaderField: "vos")
        request.setValue("998", forHTTPHeaderField: "vversioncode")
        request.setValue(Signing.signatureDate(), forHTTPHeaderField: "vdate")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await session.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        return try decodeApiAp(html)
    }

    private func acceptConsent(accessToken: String?) async throws {
        guard let url = URL(string: base + "/konto/zgody") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = formBody([
            ("HasUnacceptedOnlyOneRegulation", "true"),
            ("Consent[0].Key", "6"),
            ("Consent[0].Value", "true")
        ])
        _ = try await session.data(for: request)
    }

    // MARK: Cookies

    /// Drops all portal cookies so a stale or signed-in session cannot hijack `/logowanie`.
    private func clearPortalCookies() {
        let storage = session.configuration.httpCookieStorage ?? .shared
        guard let url = URL(string: base) else { return }
        for cookie in storage.cookies(for: url) ?? [] {
            storage.deleteCookie(cookie)
        }
    }

    // MARK: Decoding

    private func decodeApiAp(_ html: String) throws -> ApiApResponse {
        let pattern = #"<input[^>]*\bid\s*=\s*(?:"ap"|'ap'|ap\b)[^>]*>"#
        guard let tag = LoginPage.firstMatch(html, pattern)?.first,
              let raw = LoginPage.attribute(tag, "value") else {
            throw LoginError.api("Nie znaleziono danych logowania w odpowiedzi /api/ap.")
        }
        guard let data = raw.htmlUnescaped.data(using: .utf8) else {
            throw LoginError.api("Nie udało się odczytać danych logowania.")
        }
        do {
            return try JSONDecoder().decode(ApiApResponse.self, from: data)
        } catch {
            throw LoginError.api("Nieoczekiwany format odpowiedzi logowania.")
        }
    }

    private func decodeJWT(_ token: String) throws -> JwtPayload {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw LoginError.api("Nieprawidłowy token ucznia.")
        }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        guard let data = Data(base64Encoded: base64) else {
            throw LoginError.api("Nieprawidłowy token ucznia.")
        }
        do {
            return try JSONDecoder().decode(JwtPayload.self, from: data)
        } catch {
            throw LoginError.api("Token ucznia nie zawiera szkoły.")
        }
    }

    // MARK: Proof of work captcha

    private func captchaResponse(challenge: String, difficulty: UInt32, rounds: Int) -> String {
        guard difficulty > 0, rounds > 0 else { return "" }
        var buffer = Array(challenge.utf8)
        var answers: [String] = []

        for _ in 0..<rounds {
            var nonce: UInt64 = 1
            var solved = false
            while nonce < 50_000_000 {
                let digits = Array(String(nonce).utf8)
                let candidate = buffer + digits
                let digest = Array(SHA256.hash(data: candidate))
                let value = (UInt32(digest[0]) << 24)
                    | (UInt32(digest[1]) << 16)
                    | (UInt32(digest[2]) << 8)
                    | UInt32(digest[3])
                if value < difficulty {
                    answers.append(String(nonce))
                    buffer = candidate
                    solved = true
                    break
                }
                nonce += 1
            }
            if !solved { break }
        }
        return answers.joined(separator: ";")
    }

    // MARK: Tiny HTML helpers

    private func formBody(_ pairs: [(String, String)]) -> Data {
        Data(FormURLEncoding.encode(pairs).utf8)
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension String {
    var htmlUnescaped: String {
        var text = self
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#34;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&#x2F;", with: "/")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text
    }
}
