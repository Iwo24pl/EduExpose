import Foundation

/// One child visible through a Konto LIBRUS parent account.
struct LibrusPortalAccount: Decodable, Sendable {
    let id: LibrusID
    let login: String
    let accessToken: String?
    let studentName: String?
    let group: String?
    let state: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case login
        case accessToken
        case studentName
        case group
        case state
    }
}

struct LibrusPortalAccountsEnvelope: Decodable, Sendable {
    let accounts: [LibrusPortalAccount]?
    let lastModification: Int?
}

struct LibrusPortalLogin: Sendable {
    let email: String
    let password: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let accounts: [LibrusPortalAccount]
}

private struct LibrusPortalTokenEnvelope: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct LibrusAutoLoginEnvelope: Decodable {
    let token: String?
}

/// Re-establishes a child Synergia session from a portal state. The session
/// actor depends only on this protocol, which keeps the cookie transport and
/// the portal specifics separate.
protocol LibrusPortalBridging: Sendable {
    func bridge(_ state: LibrusPortalState) async throws -> (state: LibrusPortalState, cookies: [LibrusCookie])
}

/// Konto LIBRUS (portal) login and the per-child `AutoLoginToken` bridge.
///
/// This is the only flow that can enumerate several children from one parent
/// login. It deliberately keeps two jars: portal cookies and the child
/// Synergia cookies. A `LibrusPortalClient` is created per child when it is
/// used for a bridge, so children never share session cookies.
actor LibrusPortalClient: LibrusPortalBridging {
    private let transport: any LibrusTransport
    private let trace: LibrusTrace
    private let portalJar = LibrusCookieJar()
    private let childJar = LibrusCookieJar()

    init(
        transport: any LibrusTransport = URLSessionLibrusTransport(),
        trace: LibrusTrace = LibrusTrace()
    ) {
        self.transport = transport
        self.trace = trace
    }

    // MARK: Portal sign-in

    /// Signs in with the parent e-mail and returns every child account.
    func signIn(email: String, password: String) async throws -> LibrusPortalLogin {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            throw LibrusError.invalidCredentials
        }
        loginEmail = trimmedEmail
        loginPassword = password
        await portalJar.clear()

        await trace.record("portal.login.start")
        let code = try await authorizationCode()
        let token = try await exchange(code: code)
        let children = try await accounts(accessToken: token.accessToken)

        let usable = children.filter { account in
            let state = (account.state ?? "").lowercased()
            return state != "requiring_an_action" && state != "need-activation"
        }
        guard !usable.isEmpty else {
            throw LibrusError.actionRequired
        }

        await trace.record("portal.login.ok", note: "children=\(usable.count)")
        return LibrusPortalLogin(
            email: trimmedEmail,
            password: password,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresAt,
            accounts: usable
        )
    }

    /// Builds one child's Synergia cookies. `state` is returned with refreshed
    /// portal/child tokens so the caller can persist them.
    func bridge(_ state: LibrusPortalState) async throws -> (state: LibrusPortalState, cookies: [LibrusCookie]) {
        var current = state

        if current.childAccessToken.isEmpty
            || (current.childExpiresAt.map { $0 < Date().addingTimeInterval(5 * 60) } ?? true) {
            current = try await freshChild(current)
        }

        do {
            return try await bridgeChild(current)
        } catch let error as LibrusError {
            let retryable: Bool
            switch error {
            case .httpStatus(let status) where status == 401 || status == 403:
                retryable = true
            case .invalidCredentials:
                retryable = true
            default:
                retryable = false
            }
            guard retryable else {
                throw error
            }
            current = try await freshChild(current, force: true)
            return try await bridgeChild(current)
        }
    }

    // MARK: HTTP flow

    private func authorizationCode() async throws -> String {
        var url = LibrusConstants.kontoPortalAuthorizeURL
        for _ in 0..<12 {
            let response = try await send(
                LibrusRequest(
                    url: url,
                    headers: portalHeaders(referer: nil)
                ),
                jar: portalJar
            )
            if let code = Self.authorizationCode(in: response.header("location")) {
                return code
            }
            if let location = response.header("location") {
                if location.lowercased().contains("rejected_client") {
                    throw LibrusError.invalidCredentials
                }
                guard let next = LibrusHosts.resolve(location, relativeTo: response.url) else {
                    throw LibrusError.unsafeRedirect
                }
                url = next
                continue
            }
            guard (200..<300).contains(response.status) else {
                throw Self.error(for: response)
            }
            if Self.containsCaptcha(response.text) {
                throw LibrusError.captchaRequired
            }
            return try await submitLogin(page: response.text, pageURL: response.url)
        }
        throw LibrusError.unexpectedResponse
    }

    private func submitLogin(page: String, pageURL: URL) async throws -> String {
        let csrf = Self.csrfToken(in: page)
        let hidden = Self.hiddenFields(in: page)

        var form: [(String, String)] = hidden
            .filter { $0.key != "email" && $0.key != "password" }
            .map { ($0.key, $0.value) }
        form.append(("email", loginEmail))
        form.append(("password", loginPassword))

        var headers = portalHeaders(referer: pageURL.absoluteString)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        if let csrf {
            headers["X-CSRF-TOKEN"] = csrf
        }

        let body = FormURLEncoding.encode(form)
        let response = try await send(
            LibrusRequest(
                url: LibrusConstants.kontoPortalLoginURL,
                method: "POST",
                headers: headers,
                body: Data(body.utf8)
            ),
            jar: portalJar
        )

        if let code = Self.authorizationCode(in: response.header("location")) {
            return code
        }
        if let location = response.header("location") {
            if location.lowercased().contains("command=close") {
                throw LibrusError.maintenance
            }
            guard let next = LibrusHosts.resolve(location, relativeTo: response.url) else {
                throw LibrusError.unsafeRedirect
            }
            return try await authorizationCode(startingAt: next)
        }

        if Self.containsCaptcha(response.text) {
            throw LibrusError.captchaRequired
        }
        if response.status == 401 || response.status == 403 {
            throw LibrusError.invalidCredentials
        }
        let lower = response.text.lowercased()
        if lower.contains("nieprawidłow")
            || lower.contains("nieprawid")
            || lower.contains("invalid") {
            throw LibrusError.invalidCredentials
        }
        throw Self.error(for: response)
    }

    private func authorizationCode(startingAt start: URL) async throws -> String {
        var url = start
        for _ in 0..<12 {
            let response = try await send(
                LibrusRequest(url: url, headers: portalHeaders(referer: nil)),
                jar: portalJar
            )
            if let code = Self.authorizationCode(in: response.header("location")) {
                return code
            }
            if let location = response.header("location") {
                guard let next = LibrusHosts.resolve(location, relativeTo: response.url) else {
                    throw LibrusError.unsafeRedirect
                }
                url = next
                continue
            }
            if Self.containsCaptcha(response.text) {
                throw LibrusError.captchaRequired
            }
            throw Self.error(for: response)
        }
        throw LibrusError.unexpectedResponse
    }

    private var loginEmail = ""
    private var loginPassword = ""

    private func exchange(code: String) async throws -> (accessToken: String, refreshToken: String?, expiresAt: Date) {
        let body = FormURLEncoding.encode([
            ("client_id", LibrusConstants.kontoPortalClientID),
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", LibrusConstants.kontoPortalRedirectURI)
        ])
        let response = try await tokenRequest(body: body)
        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw LibrusError.unexpectedResponse
        }
        return (
            accessToken,
            response.refreshToken,
            Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 86_400))
        )
    }

    private func tokenRequest(body: String) async throws -> LibrusPortalTokenEnvelope {
        var headers = portalHeaders(referer: nil)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        let response = try await send(
            LibrusRequest(
                url: LibrusConstants.kontoPortalTokenURL,
                method: "POST",
                headers: headers,
                body: Data(body.utf8)
            ),
            jar: portalJar
        )
        guard response.status == 200 else {
            if response.status == 400 || response.status == 401 {
                throw LibrusError.invalidCredentials
            }
            throw Self.error(for: response)
        }
        do {
            return try JSONDecoder().decode(LibrusPortalTokenEnvelope.self, from: response.body)
        } catch {
            throw LibrusError.decoding(endpoint: "oauth2/access_token")
        }
    }

    private func accounts(accessToken: String) async throws -> [LibrusPortalAccount] {
        var headers = portalHeaders(referer: nil)
        headers["Authorization"] = "Bearer \(accessToken)"
        let response = try await send(
            LibrusRequest(url: LibrusConstants.kontoPortalAccountsURL, headers: headers),
            jar: portalJar
        )
        guard response.status == 200 else {
            throw Self.error(for: response)
        }
        do {
            return try JSONDecoder().decode(
                LibrusPortalAccountsEnvelope.self,
                from: response.body
            ).accounts ?? []
        } catch {
            throw LibrusError.decoding(endpoint: "v3/SynergiaAccounts")
        }
    }

    private func freshChild(_ state: LibrusPortalState, force: Bool = false) async throws -> LibrusPortalState {
        var current = state
        if force
            || current.portalAccessToken.isEmpty
            || (current.portalExpiresAt.map { $0 < Date().addingTimeInterval(60) } ?? true) {
            current = try await refreshPortal(current)
        }

        guard let url = URL(
            string: LibrusConstants.kontoPortalFreshBase.absoluteString
                + (current.accountLogin.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? current.accountLogin)
        ) else {
            throw LibrusError.unsafeURL
        }
        var headers = portalHeaders(referer: nil)
        headers["Authorization"] = "Bearer \(current.portalAccessToken)"
        let response = try await send(
            LibrusRequest(url: url, headers: headers),
            jar: portalJar
        )
        guard response.status == 200 else {
            throw Self.error(for: response)
        }
        do {
            let account = try JSONDecoder().decode(LibrusPortalAccount.self, from: response.body)
            guard let token = account.accessToken, !token.isEmpty else {
                throw LibrusError.unexpectedResponse
            }
            current.childAccessToken = token
            current.childExpiresAt = Date().addingTimeInterval(LibrusConstants.childTokenLifetime)
            return current
        } catch let error as LibrusError {
            throw error
        } catch {
            throw LibrusError.decoding(endpoint: "SynergiaAccounts/fresh")
        }
    }

    private func refreshPortal(_ state: LibrusPortalState) async throws -> LibrusPortalState {
        guard let refreshToken = state.portalRefreshToken, !refreshToken.isEmpty else {
            throw LibrusError.reauthRequired
        }
        let body = FormURLEncoding.encode([
            ("client_id", LibrusConstants.kontoPortalClientID),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken)
        ])
        let token = try await tokenRequest(body: body)
        guard let accessToken = token.accessToken, !accessToken.isEmpty else {
            throw LibrusError.reauthRequired
        }
        var current = state
        current.portalAccessToken = accessToken
        current.portalRefreshToken = token.refreshToken ?? state.portalRefreshToken
        current.portalExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 86_400))
        return current
    }

    private func bridgeChild(_ state: LibrusPortalState) async throws -> (state: LibrusPortalState, cookies: [LibrusCookie]) {
        var headers = portalHeaders(referer: nil)
        headers["Authorization"] = "Bearer \(state.childAccessToken)"
        headers["Accept"] = "application/json"
        let response = try await send(
            LibrusRequest(
                url: LibrusConstants.autoLoginTokenURL,
                method: "POST",
                headers: headers
            ),
            jar: portalJar
        )
        guard response.status == 200 else {
            throw Self.error(for: response)
        }
        let token: String
        do {
            guard let value = try JSONDecoder.vulcan().decode(LibrusAutoLoginEnvelope.self, from: response.body).token,
                  !value.isEmpty else {
                throw LibrusError.unexpectedResponse
            }
            token = value
        } catch let error as LibrusError {
            throw error
        } catch {
            throw LibrusError.decoding(endpoint: "AutoLoginToken")
        }

        await childJar.clear()
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let bridgeURL = URL(
                string: "https://synergia.librus.pl/loguj/token/\(encodedToken)/przenies/uczen/widok/centrum_powiadomien"
              ) else {
            throw LibrusError.unsafeURL
        }

        var url = bridgeURL
        for _ in 0..<12 {
            let bridge = try await send(
                LibrusRequest(url: url, headers: portalHeaders(referer: nil)),
                jar: childJar
            )
            if let location = bridge.header("location") {
                guard let next = LibrusHosts.resolve(location, relativeTo: bridge.url) else {
                    throw LibrusError.unsafeRedirect
                }
                url = next
                continue
            }
            guard (200..<300).contains(bridge.status) else {
                throw Self.error(for: bridge)
            }
            break
        }

        let cookies = await childJar.snapshotPersistable()
        let hasSession = cookies.contains {
            ($0.name == "DZIENNIKSID" || $0.name == "SDZIENNIKSID"
                || $0.name == LibrusConstants.oauthTokenCookie)
                && LibrusHosts.isSynergia($0.domain)
        }
        guard hasSession else {
            throw LibrusError.missingSession
        }
        await trace.record("portal.bridge.ok", note: "cookies=\(cookies.count)")
        return (state, cookies)
    }

    // MARK: Transport

    private func send(_ request: LibrusRequest, jar: LibrusCookieJar) async throws -> LibrusHTTPResponse {
        guard LibrusHosts.isAllowed(request.url) else {
            throw LibrusError.unsafeURL
        }
        var outgoing = request
        if outgoing.headers["User-Agent"] == nil {
            outgoing.headers["User-Agent"] = LibrusConstants.userAgent
        }
        if outgoing.headers["Accept-Language"] == nil {
            outgoing.headers["Accept-Language"] = LibrusConstants.acceptLanguage
        }
        if outgoing.headers["Cache-Control"] == nil {
            outgoing.headers["Cache-Control"] = "no-cache"
        }
        if outgoing.headers["Accept"] == nil {
            outgoing.headers["Accept"] = "*/*"
        }
        if let cookie = await jar.header(for: outgoing.url) {
            outgoing.headers["Cookie"] = cookie
        }

        let response: LibrusHTTPResponse
        do {
            response = try await transport.send(outgoing)
        } catch let error as LibrusTransportError {
            if case .cancelled = error {
                throw CancellationError()
            }
            throw LibrusError.network
        } catch {
            throw LibrusError.network
        }
        guard LibrusHosts.isAllowed(response.url) else {
            throw LibrusError.unsafeRedirect
        }
        await jar.store(response.setCookie, for: response.url)
        await trace.record(
            "portal.http",
            endpoint: LibrusTrace.endpoint(response.url),
            status: response.status
        )
        return response
    }

    private func portalHeaders(referer: String?) -> [String: String] {
        var headers: [String: String] = [
            "Accept": "*/*",
            "X-Requested-With": LibrusConstants.kontoPortalRequestedWith,
            "User-Agent": LibrusConstants.kontoPortalUserAgent
        ]
        if let referer {
            headers["Referer"] = referer
        }
        return headers
    }

    // MARK: Parsing

    static func authorizationCode(in location: String?) -> String? {
        guard let location,
              let components = URLComponents(string: location) else {
            return nil
        }
        if components.scheme?.lowercased() == "app" {
            return components.queryItems?.first(where: { $0.name == "code" })?.value
        }
        if let value = components.queryItems?.first(where: { $0.name == "code" })?.value {
            return value
        }
        guard let range = location.range(of: "code=") else { return nil }
        let tail = location[range.upperBound...]
        let value = tail.split(separator: "&").first.map(String.init) ?? ""
        return value.isEmpty ? nil : value.removingPercentEncoding ?? value
    }

    static func containsCaptcha(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["g-recaptcha", "recaptcha", "hcaptcha", "robotem", "captchavalidate"]
            .contains { lower.contains($0) }
    }

    static func csrfToken(in html: String) -> String? {
        let patterns = [
            #"<meta[^>]+name=["']csrf-token["'][^>]+content=["']([^"']+)"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']csrf-token["']"#,
            #"<input[^>]+name=["']_csrf["'][^>]+value=["']([^"']+)"#,
            #"<input[^>]+value=["']([^"']+)["'][^>]+name=["']_csrf["']"#
        ]
        for pattern in patterns {
            if let value = firstMatch(pattern, in: html) {
                return value
            }
        }
        return nil
    }

    static func hiddenFields(in html: String) -> [String: String] {
        let pattern = #"<input\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var fields: [String: String] = [:]
        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard tag.lowercased().contains("hidden") else { continue }
            guard let name = attribute("name", in: tag),
                  let value = attribute("value", in: tag) else {
                continue
            }
            fields[name] = value
        }
        return fields
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstMatch("\(escaped)=[\"']([^\"']*)[\"']", in: tag)
            ?? firstMatch("\(escaped)\\s*=\\s*([^\\s>]+)", in: tag)
    }

    private static func error(for response: LibrusHTTPResponse) -> LibrusError {
        switch response.status {
        case 401, 403:
            return .invalidCredentials
        case 429:
            return .rateLimited
        case 503:
            return .maintenance
        case 502, 504:
            return .retryLater(status: response.status)
        default:
            if containsCaptcha(response.text) { return .captchaRequired }
            return .httpStatus(response.status)
        }
    }
}
