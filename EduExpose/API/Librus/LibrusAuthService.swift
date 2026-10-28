import Foundation

/// Librus sign-in and session recreation.
///
/// The Konto LIBRUS portal flow is preferred because it enumerates every
/// child from a parent login. When the portal refuses a flow (a school that
/// disabled it, a changed portal page, or a single-child Synergia account),
/// the documented web-cookie flow remains as a fallback.
struct LibrusAuthService: RegistryAuthService {
    let transport: any LibrusTransport
    let clock: any LibrusClock
    let trace: LibrusTrace
    let onSessionUpdate: LibrusSessionObserver?

    var provider: EduRegistry { .librus }

    init(
        transport: any LibrusTransport = URLSessionLibrusTransport(),
        clock: any LibrusClock = LibrusSystemClock(),
        trace: LibrusTrace = LibrusTrace(),
        onSessionUpdate: LibrusSessionObserver? = nil
    ) {
        self.transport = transport
        self.clock = clock
        self.trace = trace
        self.onSessionUpdate = onSessionUpdate
    }

    func signIn(login: String, password: String) async throws -> [RegistryStudent] {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty, !password.isEmpty else {
            throw LibrusError.invalidCredentials
        }

        do {
            let portal = LibrusPortalClient(transport: transport, trace: trace)
            let result = try await portal.signIn(email: trimmedLogin, password: password)
            let students = try await makePortalStudents(result)
            if !students.isEmpty {
                return students
            }
        } catch let error as LibrusError {
            // A portal page that cannot be parsed or an API that a school
            // disabled must not block a working single-child web login.
            guard Self.shouldFallBackToWeb(for: error) else {
                throw error
            }
            await trace.record("portal.fallback", note: error.traceCode)
        }

        return try await signInWithWeb(login: trimmedLogin, password: password)
    }

    /// Rebuilds the live actor for an already stored account. The session
    /// may be restored after a cold launch; the actor refreshes or asks for
    /// re-authentication as needed.
    func makeSession(
        for student: RegistryStudent,
        onSessionUpdate: LibrusSessionObserver? = nil
    ) async throws -> LibrusSessionActor {
        guard case let .librus(session) = student.session else {
            throw LibrusError.missingSession
        }
        let observer = onSessionUpdate ?? self.onSessionUpdate
        if session.method == .portal, let state = session.portal {
            let bridge = LibrusPortalClient(transport: transport, trace: trace)
            return LibrusSessionActor(
                session: session,
                credentials: LibrusCredentials(
                    login: state.email,
                    password: state.password ?? session.password
                ),
                transport: transport,
                clock: clock,
                trace: trace,
                onSessionUpdate: observer,
                portalBridge: bridge
            )
        }
        return LibrusSessionActor(
            session: session,
            credentials: LibrusCredentials(login: session.login, password: session.password),
            transport: transport,
            clock: clock,
            trace: trace,
            onSessionUpdate: observer
        )
    }

    // MARK: Portal children

    private func makePortalStudents(_ login: LibrusPortalLogin) async throws -> [RegistryStudent] {
        var students: [RegistryStudent] = []
        var firstError: (any Error)?

        for item in login.accounts {
            do {
                let state = LibrusPortalState(
                    email: login.email,
                    password: login.password,
                    accountID: item.id.stableInt,
                    accountLogin: item.login,
                    portalAccessToken: login.accessToken,
                    portalRefreshToken: login.refreshToken,
                    portalExpiresAt: login.expiresAt,
                    childAccessToken: item.accessToken ?? "",
                    childExpiresAt: nil
                )
                let bridge = LibrusPortalClient(transport: transport, trace: trace)
                let bridged = try await bridge.bridge(state)
                let session = LibrusSession(
                    login: login.email,
                    password: login.password,
                    cookies: bridged.cookies,
                    loggedInAt: clock.now,
                    loginCount: 1,
                    lastRefreshAt: nil,
                    lastRefreshFailedAt: nil,
                    authMethod: .portal,
                    portal: bridged.state
                )
                let actor = LibrusSessionActor(
                    session: session,
                    credentials: LibrusCredentials(
                        login: login.email,
                        password: login.password
                    ),
                    transport: transport,
                    clock: clock,
                    trace: trace,
                    onSessionUpdate: onSessionUpdate,
                    portalBridge: bridge
                )
                let restored = try await actor.signIn()
                let client = LibrusAPIClient(session: actor, trace: trace)
                let account = try await LibrusProfileLoader(client: client).load()
                students.append(RegistryStudent(
                    id: "librus-\(item.id.raw)-\(account.id)",
                    provider: .librus,
                    account: account,
                    session: .librus(restored),
                    isEnabled: true
                ))
            } catch {
                if firstError == nil { firstError = error }
                await trace.record("portal.child.fail", note: "child")
            }
        }

        if students.isEmpty, let firstError {
            throw firstError
        }
        return students.sorted { $0.displayName < $1.displayName }
    }

    // MARK: Single-child fallback

    private func signInWithWeb(login: String, password: String) async throws -> [RegistryStudent] {
        let actor = LibrusSessionActor(
            session: nil,
            credentials: LibrusCredentials(login: login, password: password),
            transport: transport,
            clock: clock,
            trace: trace,
            onSessionUpdate: onSessionUpdate
        )
        _ = try await actor.signIn(force: true)
        guard let session = await actor.snapshot() else {
            throw LibrusError.missingSession
        }

        let client = LibrusAPIClient(session: actor, trace: trace)
        let account = try await LibrusProfileLoader(client: client).load()
        return [RegistryStudent(
            id: "librus-\(account.id)",
            provider: .librus,
            account: account,
            session: .librus(session),
            isEnabled: true
        )]
    }

    private static func shouldFallBackToWeb(for error: LibrusError) -> Bool {
        switch error {
        case .unexpectedResponse,
             .unsafeURL,
             .unsafeRedirect,
             .decoding,
             .moduleUnavailable,
             .insufficientScopes,
             .missingSession,
             .httpStatus(404),
             .httpStatus(405),
             .httpStatus(400):
            return true
        default:
            return false
        }
    }
}
