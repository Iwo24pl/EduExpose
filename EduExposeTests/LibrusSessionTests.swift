import Foundation
import Testing
@testable import EduExpose

// MARK: - Test doubles

final class MockLibrusTransport: LibrusTransport, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: Data = Data()
        var headers: [String: String] = [:]
        var setCookie: [String] = []
        var url: URL? = nil
    }

    private struct Entry {
        let matcher: @Sendable (URL) -> Bool
        var replies: [Reply]
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var recorded: [LibrusRequest] = []

    func enqueue(_ matcher: @escaping @Sendable (URL) -> Bool, _ reply: Reply) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(matcher: matcher, replies: [reply]))
    }

    func send(_ request: LibrusRequest) async throws -> LibrusHTTPResponse {
        let reply = try withLock { () throws -> Reply in
            recorded.append(request)
            guard let index = entries.firstIndex(where: {
                $0.matcher(request.url) && !$0.replies.isEmpty
            }) else {
                throw LibrusTransportError.network
            }
            var entry = entries[index]
            let reply = entry.replies.removeFirst()
            if entry.replies.isEmpty {
                entries.remove(at: index)
            } else {
                entries[index] = entry
            }
            return reply
        }
        return LibrusHTTPResponse(
            url: reply.url ?? request.url,
            status: reply.status,
            headers: reply.headers,
            setCookie: reply.setCookie,
            body: reply.body
        )
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var requests: [LibrusRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func count(path: String) -> Int {
        requests.filter { $0.url.path == path }.count
    }
}

final class FakeLibrusClock: LibrusClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(seconds)
        lock.unlock()
    }
}

// MARK: - Fixtures

private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
private let meURL = URL(string: "https://synergia.librus.pl/gateway/api/2.0/Me")!

private func makeSession(
    now: Date = baseDate,
    age: TimeInterval = 0,
    token: String = "old-token"
) -> LibrusSession {
    LibrusSession(
        login: "user@example.com",
        password: "secret",
        cookies: [
            LibrusCookie(
                name: "oauth_token",
                value: token,
                domain: "synergia.librus.pl",
                path: "/",
                expiresAt: nil,
                isSecure: true,
                isHTTPOnly: true
            )
        ],
        loggedInAt: now.addingTimeInterval(-age),
        loginCount: 1,
        lastRefreshAt: nil,
        lastRefreshFailedAt: nil
    )
}

private func enqueueLogin(
    _ transport: MockLibrusTransport,
    token: String = "login-token",
    failureBody: String? = nil,
    captcha: Bool = false
) {
    transport.enqueue({ url in
        url.host == "synergia.librus.pl" && url.path == "/loguj/portalRodzina"
    }, .init(
        status: 302,
        headers: ["location": "https://api.librus.pl/OAuth/Authorization?client_id=46&response_type=code&scope=mydata&state=x"]
    ))

    transport.enqueue({ url in
        url.host == "api.librus.pl"
            && url.path == "/OAuth/Authorization"
            && url.query?.contains("response_type=code") == true
    }, .init(status: 200, setCookie: ["api_session=1; Domain=api.librus.pl; Path=/"]))

    let body: String
    if let failureBody {
        body = failureBody
    } else if captcha {
        body = "<html>g-recaptcha</html>"
    } else {
        body = #"{"status":"ok","goTo":"/OAuth/Authorization/2FA?client_id=46"}"#
    }
    transport.enqueue({ url in
        url.host == "api.librus.pl"
            && url.path == "/OAuth/Authorization"
            && url.query == "client_id=46"
    }, .init(status: 200, body: Data(body.utf8)))

    if failureBody == nil && !captcha {
        transport.enqueue({ url in
            url.host == "api.librus.pl" && url.path == "/OAuth/Authorization/2FA"
        }, .init(
            status: 302,
            headers: ["location": "https://synergia.librus.pl/loguj/ok"],
            setCookie: ["oauth_token=\(token); Domain=synergia.librus.pl; Path=/; Secure; HttpOnly"]
        ))
        transport.enqueue({ url in
            url.host == "synergia.librus.pl" && url.path == "/loguj/ok"
        }, .init(status: 200))
    }
}

// MARK: - Tests

@Suite("Librus session")
struct LibrusSessionTests {
    @Test("Login follows the handshake and stores the oauth_token cookie")
    func loginStoresToken() async throws {
        let transport = MockLibrusTransport()
        enqueueLogin(transport)
        let clock = FakeLibrusClock(baseDate)
        let actor = LibrusSessionActor(
            session: nil,
            credentials: LibrusCredentials(login: "user@example.com", password: "secret"),
            transport: transport,
            clock: clock,
            trace: LibrusTrace()
        )

        let session = try await actor.signIn(force: true)
        let hasToken = session.cookies.contains {
            $0.name == "oauth_token" && $0.value == "login-token"
        }

        #expect(session.loginCount == 1)
        #expect(hasToken)
        #expect(transport.count(path: "/loguj/portalRodzina") == 1)
        #expect(transport.count(path: "/OAuth/Authorization/2FA") == 1)
    }

    @Test("A login rejection is invalid credentials")
    func invalidCredentials() async {
        let transport = MockLibrusTransport()
        enqueueLogin(transport, failureBody: #"{"status":"error"}"#)
        let actor = LibrusSessionActor(
            session: nil,
            credentials: LibrusCredentials(login: "user", password: "wrong"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        do {
            _ = try await actor.signIn(force: true)
            Issue.record("Expected invalid credentials")
        } catch let error as LibrusError {
            #expect(error == .invalidCredentials)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A captcha marker maps to captchaRequired")
    func captcha() async {
        let transport = MockLibrusTransport()
        enqueueLogin(transport, captcha: true)
        let actor = LibrusSessionActor(
            session: nil,
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        do {
            _ = try await actor.signIn(force: true)
            Issue.record("Expected captcha")
        } catch let error as LibrusError {
            #expect(error == .captchaRequired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("A session older than two hours refreshes before a request")
    func refreshesBeforeRequest() async throws {
        let transport = MockLibrusTransport()
        let clock = FakeLibrusClock(baseDate)
        transport.enqueue({ url in
            url.host == "synergia.librus.pl" && url.path == "/refreshToken"
        }, .init(
            status: 200,
            setCookie: ["oauth_token=new-token; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly"]
        ))
        transport.enqueue({ url in
            url.path == "/gateway/api/2.0/Me"
        }, .init(status: 200, body: Data("{}".utf8)))

        let actor = LibrusSessionActor(
            session: makeSession(now: baseDate, age: 3 * 3600),
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: clock,
            trace: LibrusTrace()
        )

        let response = try await actor.send(LibrusRequest(url: meURL))
        let snapshot = await actor.snapshot()
        let hasNewToken = snapshot?.cookies.contains {
            $0.name == "oauth_token" && $0.value == "new-token"
        } ?? false

        #expect(response.status == 200)
        #expect(transport.count(path: "/refreshToken") == 1)
        #expect(hasNewToken)
    }

    @Test("401 refreshes once and retries the request")
    func unauthorizedRefreshesOnce() async throws {
        let transport = MockLibrusTransport()
        transport.enqueue({ url in
            url.path == "/gateway/api/2.0/Me"
        }, .init(status: 401, body: Data(#"{"Message":"Token expired"}"#.utf8)))
        transport.enqueue({ url in
            url.path == "/refreshToken"
        }, .init(
            status: 200,
            setCookie: ["oauth_token=new-token; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly"]
        ))
        transport.enqueue({ url in
            url.path == "/gateway/api/2.0/Me"
        }, .init(status: 200, body: Data("{}".utf8)))

        let actor = LibrusSessionActor(
            session: makeSession(),
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        let response = try await actor.send(LibrusRequest(url: meURL))

        #expect(response.status == 200)
        #expect(transport.count(path: "/refreshToken") == 1)
        #expect(transport.count(path: "/gateway/api/2.0/Me") == 2)
    }

    @Test("A 401 immediately after a refresh forces one login")
    func unauthorizedAfterRefreshLogsIn() async throws {
        let transport = MockLibrusTransport()
        transport.enqueue({ url in
            url.path == "/gateway/api/2.0/Me"
        }, .init(status: 401))
        transport.enqueue({ url in
            url.path == "/refreshToken"
        }, .init(
            status: 200,
            setCookie: ["oauth_token=refreshed; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly"]
        ))
        transport.enqueue({ url in
            url.path == "/gateway/api/2.0/Me"
        }, .init(status: 401))
        enqueueLogin(transport, token: "login-token")
        transport.enqueue({ url in
            url.path == "/gateway/api/2.0/Me"
        }, .init(status: 200, body: Data("{}".utf8)))

        let actor = LibrusSessionActor(
            session: makeSession(),
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        let response = try await actor.send(LibrusRequest(url: meURL))
        let snapshot = await actor.snapshot()

        #expect(response.status == 200)
        #expect(transport.count(path: "/refreshToken") == 1)
        #expect(transport.count(path: "/loguj/portalRodzina") == 1)
        #expect(snapshot?.loginCount == 2)
    }

    @Test("A 403 module refusal never triggers a login")
    func forbiddenIsModuleUnavailable() async {
        let transport = MockLibrusTransport()
        transport.enqueue({ _ in true }, .init(status: 403))

        let actor = LibrusSessionActor(
            session: makeSession(),
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        do {
            _ = try await actor.send(LibrusRequest(url: meURL))
            Issue.record("Expected module unavailable")
        } catch let error as LibrusError {
            guard case .moduleUnavailable(_, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(transport.count(path: "/loguj/portalRodzina") == 0)
        #expect(transport.count(path: "/refreshToken") == 0)
    }

    @Test("401 Insufficient scopes is a module refusal, not a dead session")
    func insufficientScopes() async {
        let transport = MockLibrusTransport()
        transport.enqueue({ _ in true }, .init(
            status: 401,
            body: Data(#"{"Message":"Insufficient scopes"}"#.utf8)
        ))

        let actor = LibrusSessionActor(
            session: makeSession(),
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        do {
            _ = try await actor.send(LibrusRequest(url: meURL))
            Issue.record("Expected insufficient scopes")
        } catch let error as LibrusError {
            guard case .insufficientScopes(_) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(transport.count(path: "/refreshToken") == 0)
    }

    @Test("503 is maintenance and never triggers a login")
    func maintenance() async {
        let transport = MockLibrusTransport()
        transport.enqueue({ _ in true }, .init(status: 503))

        let actor = LibrusSessionActor(
            session: makeSession(),
            credentials: LibrusCredentials(login: "user", password: "secret"),
            transport: transport,
            clock: FakeLibrusClock(baseDate),
            trace: LibrusTrace()
        )

        do {
            _ = try await actor.send(LibrusRequest(url: meURL))
            Issue.record("Expected maintenance")
        } catch let error as LibrusError {
            #expect(error == .maintenance)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(transport.count(path: "/loguj/portalRodzina") == 0)
    }

    @Test("A failed login is not retried within the backoff window")
    func loginBackoff() async {
        let transport = MockLibrusTransport()
        enqueueLogin(transport, failureBody: #"{"status":"error"}"#)
        let clock = FakeLibrusClock(baseDate)
        let actor = LibrusSessionActor(
            session: nil,
            credentials: LibrusCredentials(login: "user", password: "wrong"),
            transport: transport,
            clock: clock,
            trace: LibrusTrace()
        )

        do {
            _ = try await actor.signIn(force: true)
        } catch {
            // Expected.
        }
        let afterFirst = transport.count(path: "/loguj/portalRodzina")

        do {
            _ = try await actor.signIn(force: true)
        } catch {
            // Expected: served from the backoff without a request.
        }
        #expect(transport.count(path: "/loguj/portalRodzina") == afterFirst)

        clock.advance(61)
        enqueueLogin(transport, token: "after-backoff")
        let session = try? await actor.signIn(force: true)
        let hasToken = session?.cookies.contains { $0.value == "after-backoff" } ?? false
        #expect(hasToken)
    }
}
