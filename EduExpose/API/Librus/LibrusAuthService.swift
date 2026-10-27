import Foundation

/// Librus sign-in and session recreation.
///
/// The web-cookie flow exposes one student per session; multi-child import
/// is intentionally a separate follow-up. The caller receives a complete
/// `RegistryStudent` whose `LibrusSession` can be persisted in the Keychain.
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
        return LibrusSessionActor(
            session: session,
            credentials: LibrusCredentials(login: session.login, password: session.password),
            transport: transport,
            clock: clock,
            trace: trace,
            onSessionUpdate: onSessionUpdate ?? self.onSessionUpdate
        )
    }
}
