import Foundation

protocol LibrusClock: Sendable {
    var now: Date { get }
}

struct LibrusSystemClock: LibrusClock {
    var now: Date { Date() }
}

/// One authenticated Librus account.
///
/// The actor owns the cookie jar, the login/refresh single-flight tasks and
/// the expiry policy. Callers only see `send`, `signIn` and snapshots.
actor LibrusSessionActor {
    private let credentials: LibrusCredentials
    private let transport: any LibrusTransport
    private let jar: LibrusCookieJar
    private let clock: any LibrusClock
    private let trace: LibrusTrace
    private let onSessionUpdate: LibrusSessionObserver?
    private let portalBridge: (any LibrusPortalBridging)?

    private var session: LibrusSession?
    private var loginTask: Task<LibrusSession, any Error>?
    private var refreshTask: Task<Bool, Never>?
    private var lastLoginFailure: LibrusError?
    private var lastLoginFailureAt: Date?
    private var reauthRequired = false

    init(
        session: LibrusSession?,
        credentials: LibrusCredentials,
        transport: any LibrusTransport,
        clock: any LibrusClock = LibrusSystemClock(),
        trace: LibrusTrace = LibrusTrace(),
        onSessionUpdate: LibrusSessionObserver? = nil,
        portalBridge: (any LibrusPortalBridging)? = nil
    ) {
        self.session = session
        self.credentials = credentials
        self.transport = transport
        self.jar = LibrusCookieJar(session?.cookies ?? [])
        self.clock = clock
        self.trace = trace
        self.onSessionUpdate = onSessionUpdate
        self.portalBridge = portalBridge
    }

    // MARK: Public state

    func snapshot() async -> LibrusSession? {
        guard var current = session else { return nil }
        current.cookies = await jar.snapshotPersistable()
        session = current
        return current
    }

    func loginCount() -> Int {
        session?.loginCount ?? 0
    }

    func hasCookie(named name: String, domain: String) async -> Bool {
        await jar.has(name: name, domain: domain)
    }

    func resetReauthRequired() {
        reauthRequired = false
    }

    func clear() async {
        session = nil
        reauthRequired = false
        lastLoginFailure = nil
        lastLoginFailureAt = nil
        await jar.clear()
    }

    // MARK: Authentication

    /// Returns a usable session, refreshing or logging in as needed.
    @discardableResult
    func signIn(force: Bool = false) async throws -> LibrusSession {
        if force {
            return try await loginShared()
        }
        if reauthRequired {
            throw LibrusError.reauthRequired
        }
        guard let current = session else {
            return try await loginShared()
        }

        let age = clock.now.timeIntervalSince(current.loggedInAt)
        let lifetime = current.method == .portal
            ? LibrusConstants.portalSessionLifetime
            : LibrusConstants.sessionLifetime
        let refreshAfter = current.method == .portal
            ? LibrusConstants.portalSessionRefreshAfter
            : LibrusConstants.sessionRefreshAfter
        if age >= lifetime - LibrusConstants.sessionSafetyMargin {
            return try await loginShared()
        }
        if age >= refreshAfter {
            if await refreshShared() {
                if let refreshed = session {
                    return refreshed
                }
            }
            // A failed refresh alone is not proof that the session is dead.
            // Keep using it while it is inside its lifetime; a real 401 will
            // force the login path from `send`.
            if isValid(current) {
                return current
            }
            return try await loginShared()
        }
        return current
    }

    private func isValid(_ session: LibrusSession) -> Bool {
        let age = clock.now.timeIntervalSince(session.loggedInAt)
        let lifetime = session.method == .portal
            ? LibrusConstants.portalSessionLifetime
            : LibrusConstants.sessionLifetime
        return age < lifetime - LibrusConstants.sessionSafetyMargin
    }

    /// Sends one request. `authenticated` is false only for raw transport
    /// probes; normal data calls use the default.
    func send(_ request: LibrusRequest, authenticated: Bool = true) async throws -> LibrusHTTPResponse {
        guard LibrusHosts.isAllowed(request.url) else {
            throw LibrusError.unsafeURL
        }
        if authenticated {
            _ = try await signIn(force: false)
        }

        let since = session?.loginCount ?? 0
        let refreshedRecently: Bool
        if let lastRefreshAt = session?.lastRefreshAt {
            refreshedRecently = clock.now.timeIntervalSince(lastRefreshAt) < 2 * 60
        } else {
            refreshedRecently = false
        }
        var didRefresh = refreshedRecently
        var didLogin = false
        var currentRequest = request
        var redirects = 0

        for _ in 0..<8 {
            let response: LibrusHTTPResponse
            do {
                response = try await sendRaw(currentRequest)
            } catch let error as LibrusError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LibrusError.network
            }

            guard LibrusHosts.isAllowed(response.url) else {
                throw LibrusError.unsafeRedirect
            }

            switch response.status {
            case 200..<300:
                return response

            case 300..<400:
                guard currentRequest.followsRedirects,
                      redirects < 5,
                      let location = response.header("location"),
                      let next = LibrusHosts.resolve(location, relativeTo: response.url) else {
                    throw LibrusError.unsafeRedirect
                }
                redirects += 1
                currentRequest.url = next
                continue

            case 401:
                if LibrusHosts.isDataGateway(response.url),
                   response.text.lowercased().contains("insufficient scopes") {
                    throw LibrusError.insufficientScopes(
                        endpoint: LibrusTrace.endpoint(response.url)
                    )
                }
                guard authenticated else {
                    throw LibrusError.invalidCredentials
                }
                if !didRefresh {
                    didRefresh = true
                    if await refreshShared() {
                        continue
                    }
                }
                if !didLogin {
                    didLogin = true
                    try await loginIfNeeded(since: since)
                    continue
                }
                reauthRequired = true
                throw LibrusError.sessionExpired(status: 401)

            case 403:
                throw LibrusError.moduleUnavailable(
                    endpoint: LibrusTrace.endpoint(response.url),
                    status: 403
                )

            case 429:
                throw LibrusError.rateLimited

            case 503:
                throw LibrusError.maintenance

            case 502, 504:
                throw LibrusError.retryLater(status: response.status)

            default:
                throw LibrusError.httpStatus(response.status)
            }
        }

        throw LibrusError.sessionExpired(status: 401)
    }

    // MARK: Login and refresh

    private func loginIfNeeded(since: Int) async throws {
        if (session?.loginCount ?? 0) != since {
            return
        }
        _ = try await loginShared()
    }

    private func loginShared() async throws -> LibrusSession {
        if let loginTask {
            return try await loginTask.value
        }
        let task = Task { try await self.performLogin() }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    private func performLogin() async throws -> LibrusSession {
        let now = clock.now
        if let lastLoginFailure,
           let lastLoginFailureAt,
           now.timeIntervalSince(lastLoginFailureAt) < LibrusConstants.loginBackoff {
            throw lastLoginFailure
        }

        await trace.record("login.start")
        do {
            let cookies: [LibrusCookie]
            let portalState: LibrusPortalState?

            if let current = session, current.method == .portal {
                guard let portalBridge, let state = current.portal else {
                    throw LibrusError.reauthRequired
                }
                let bridged = try await portalBridge.bridge(state)
                await jar.clear()
                await jar.restore(bridged.cookies)
                cookies = await jar.snapshotPersistable()
                portalState = bridged.state
            } else {
                try await handshake()
                cookies = await jar.snapshotPersistable()
                guard cookies.contains(where: {
                    $0.name == LibrusConstants.oauthTokenCookie
                        && LibrusHosts.isSynergia($0.domain)
                }) else {
                    throw LibrusError.unexpectedResponse
                }
                portalState = nil
            }

            let count = (session?.loginCount ?? 0) + 1
            let newSession = LibrusSession(
                login: credentials.login,
                password: credentials.password,
                cookies: cookies,
                loggedInAt: now,
                loginCount: count,
                lastRefreshAt: nil,
                lastRefreshFailedAt: nil,
                authMethod: portalState == nil ? .web : .portal,
                portal: portalState
            )
            session = newSession
            reauthRequired = false
            lastLoginFailure = nil
            lastLoginFailureAt = nil
            await trace.record("login.ok")
            if let onSessionUpdate {
                await onSessionUpdate(newSession)
            }
            return newSession
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let mapped = Self.map(error)
            lastLoginFailure = mapped
            lastLoginFailureAt = now
            if mapped == .invalidCredentials
                || mapped == .captchaRequired
                || mapped == .actionRequired
                || mapped == .reauthRequired {
                reauthRequired = true
            }

            var invalid = session ?? LibrusSession(
                login: credentials.login,
                password: credentials.password,
                cookies: [],
                loggedInAt: .distantPast,
                loginCount: 0,
                lastRefreshAt: nil,
                lastRefreshFailedAt: nil
            )
            invalid.cookies = await jar.snapshotPersistable()
            invalid.loggedInAt = .distantPast
            session = invalid
            await trace.record("login.fail", note: mapped.traceCode)
            if let onSessionUpdate {
                await onSessionUpdate(invalid)
            }
            throw mapped
        }
    }

    private func refreshShared() async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return await task.value
    }

    private func performRefresh() async -> Bool {
        guard var current = session else { return false }
        let now = clock.now
        if let failedAt = current.lastRefreshFailedAt,
           now.timeIntervalSince(failedAt) < LibrusConstants.refreshBackoff {
            return false
        }

        if current.method == .portal {
            return await performPortalRefresh(current, now: now)
        }

        let jarCookies = await jar.snapshot()
        let oldToken = jarCookies.first {
            $0.name == LibrusConstants.oauthTokenCookie
                && LibrusHosts.isSynergia($0.domain)
        }?.value

        await trace.record("refresh.start")
        do {
            let response = try await sendRaw(LibrusRequest(url: LibrusConstants.refreshURL))
            guard response.status == 200 else {
                throw LibrusError.httpStatus(response.status)
            }
            let cookies = await jar.snapshotPersistable()
            guard let newToken = cookies.first(where: {
                $0.name == LibrusConstants.oauthTokenCookie
                    && LibrusHosts.isSynergia($0.domain)
            }), newToken.value != oldToken else {
                throw LibrusError.unexpectedResponse
            }

            current.loggedInAt = now
            current.lastRefreshAt = now
            current.lastRefreshFailedAt = nil
            current.cookies = cookies
            session = current
            await trace.record("refresh.ok")
            if let onSessionUpdate {
                await onSessionUpdate(current)
            }
            return true
        } catch {
            current.lastRefreshFailedAt = now
            current.cookies = await jar.snapshotPersistable()
            session = current
            await trace.record("refresh.fail")
            if let onSessionUpdate {
                await onSessionUpdate(current)
            }
            return false
        }
    }

    // MARK: Handshake

    private func performPortalRefresh(_ current: LibrusSession, now: Date) async -> Bool {
        guard let portalBridge, let state = current.portal else {
            return false
        }
        await trace.record("refresh.start")
        do {
            let bridged = try await portalBridge.bridge(state)
            await jar.clear()
            await jar.restore(bridged.cookies)
            let cookies = await jar.snapshotPersistable()
            guard cookies.contains(where: {
                ($0.name == "DZIENNIKSID" || $0.name == "SDZIENNIKSID")
                    && LibrusHosts.isSynergia($0.domain)
            }) else {
                throw LibrusError.unexpectedResponse
            }

            var updated = current
            updated.loggedInAt = now
            updated.lastRefreshAt = now
            updated.lastRefreshFailedAt = nil
            updated.cookies = cookies
            updated.authMethod = .portal
            updated.portal = bridged.state
            session = updated
            await trace.record("refresh.ok")
            if let onSessionUpdate {
                await onSessionUpdate(updated)
            }
            return true
        } catch {
            var failed = current
            failed.lastRefreshFailedAt = now
            failed.cookies = await jar.snapshotPersistable()
            session = failed
            await trace.record("refresh.fail")
            if let onSessionUpdate {
                await onSessionUpdate(failed)
            }
            return false
        }
    }

    private func handshake() async throws {
        guard let password = credentials.password, !password.isEmpty else {
            throw LibrusError.reauthRequired
        }

        let portal = try await sendRaw(LibrusRequest(url: LibrusConstants.portalLoginURL))
        try checkRetryLater(portal)
        guard let portalLocation = portal.header("location"),
              let authorizationURL = LibrusHosts.resolve(portalLocation, relativeTo: portal.url) else {
            throw LibrusError.unexpectedResponse
        }

        let authorization = try await sendRaw(LibrusRequest(url: authorizationURL))
        try checkRetryLater(authorization)
        guard authorization.status == 200 || (300..<400).contains(authorization.status) else {
            throw LibrusError.httpStatus(authorization.status)
        }

        let form = FormURLEncoding.encode([
            ("action", "login"),
            ("login", credentials.login),
            ("pass", password)
        ])
        var headers = LibrusConstants.loginHeaders
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        let loginResponse = try await sendRaw(LibrusRequest(
            url: LibrusConstants.authorizationURL,
            method: "POST",
            headers: headers,
            body: Data(form.utf8)
        ))
        try checkRetryLater(loginResponse)
        if Self.containsCaptcha(loginResponse.text) {
            throw LibrusError.captchaRequired
        }
        if loginResponse.status == 400 || loginResponse.status == 401 {
            throw LibrusError.invalidCredentials
        }
        guard loginResponse.status == 200 else {
            throw LibrusError.httpStatus(loginResponse.status)
        }

        let data = Data(loginResponse.text.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let goTo = object["goTo"] as? String,
              let firstURL = LibrusHosts.resolve(goTo, relativeTo: LibrusConstants.authorizationURL) else {
            throw LibrusError.invalidCredentials
        }

        var currentURL = firstURL
        var hops = 0
        while true {
            let response = try await sendRaw(LibrusRequest(url: currentURL))
            try checkRetryLater(response)
            if Self.containsCaptcha(response.text) {
                throw LibrusError.captchaRequired
            }
            if response.text.contains("rejected_client") {
                throw LibrusError.unexpectedResponse
            }
            guard let location = response.header("location") else {
                break
            }
            hops += 1
            guard hops <= LibrusConstants.maxOAuthRedirects,
                  let next = LibrusHosts.resolve(location, relativeTo: response.url) else {
                throw LibrusError.unsafeRedirect
            }
            currentURL = next
        }

        let hasToken = await jar.has(
            name: LibrusConstants.oauthTokenCookie,
            domain: "synergia.librus.pl"
        )
        guard hasToken else {
            throw LibrusError.unexpectedResponse
        }
    }

    private func sendRaw(_ request: LibrusRequest) async throws -> LibrusHTTPResponse {
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
            "http",
            endpoint: LibrusTrace.endpoint(response.url),
            status: response.status
        )
        return response
    }

    private func checkRetryLater(_ response: LibrusHTTPResponse) throws {
        switch response.status {
        case 429:
            throw LibrusError.rateLimited
        case 503:
            throw LibrusError.maintenance
        case 502, 504:
            throw LibrusError.retryLater(status: response.status)
        default:
            return
        }
    }

    private static func containsCaptcha(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["captcha", "recaptcha", "g-recaptcha", "hcaptcha", "robotem"]
            .contains { lower.contains($0) }
    }

    private static func map(_ error: any Error) -> LibrusError {
        if let error = error as? LibrusError {
            return error
        }
        return .network
    }
}
