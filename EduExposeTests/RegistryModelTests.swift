import Foundation
import Testing
@testable import EduExpose

@Suite("Registry storage model")
struct RegistryModelTests {
    private func account() -> Account {
        Account(
            classDisplay: "7d",
            infoDisplay: "Librus",
            unit: SchoolUnit(
                id: 3,
                symbol: "LIBRUS",
                short: "Librus",
                restURL: "librus",
                name: "Szkoła",
                displayName: "Szkoła"
            ),
            constituentUnit: ConstituentUnit(id: 3, short: "LIBRUS", name: "Szkoła"),
            pupil: Pupil(id: 20, firstName: "Ola", secondName: nil, surname: "Kowalska"),
            periods: nil,
            journal: nil,
            messageBox: nil
        )
    }

    @Test("A Librus session survives a Keychain-style round trip")
    func librusRoundTrip() throws {
        let session = LibrusSession(
            login: "parent@example.com",
            password: "secret",
            cookies: [
                LibrusCookie(
                    name: "DeviceCookie",
                    value: "device",
                    domain: "api.librus.pl",
                    path: "/OAuth",
                    expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
                    isSecure: true,
                    isHTTPOnly: true
                )
            ],
            loggedInAt: Date(timeIntervalSince1970: 1_800_000_000),
            loginCount: 3,
            lastRefreshAt: nil,
            lastRefreshFailedAt: nil
        )
        let student = RegistryStudent(
            id: "librus-3-20",
            provider: .librus,
            account: account(),
            session: .librus(session),
            isEnabled: true
        )

        let data = try JSONEncoder().encode(student)
        let decoded = try JSONDecoder().decode(RegistryStudent.self, from: data)

        #expect(decoded.provider == .librus)
        #expect(decoded.id == "librus-3-20")
        guard case let .librus(restored) = decoded.session else {
            Issue.record("Expected a Librus session")
            return
        }
        #expect(restored.loginCount == 3)
        #expect(restored.cookies.first?.path == "/OAuth")
    }

    @Test("An eduVULCAN session survives a Keychain-style round trip")
    func eduVulcanRoundTrip() throws {
        let credential = HebeCredential(
            type: "RSA",
            restUrl: "https://lekcjaplus.vulcan.net.pl/opole/OpoleZSE/api",
            certificate: "cert",
            privateKey: "key",
            fingerprint: "fp",
            deviceId: "device",
            deviceOs: "iOS",
            deviceModel: "iPhone",
            notificationToken: nil
        )
        let student = RegistryStudent(
            id: "1-2-3-4",
            provider: .eduVulcan,
            account: account(),
            session: .eduVulcan(EduVulcanSession(
                credential: credential,
                restURL: "https://lekcjaplus.vulcan.net.pl/opole/OpoleZSE/api",
                tenant: "opole",
                login: "login",
                password: "password"
            )),
            isEnabled: true
        )

        let data = try JSONEncoder().encode(student)
        let decoded = try JSONDecoder().decode(RegistryStudent.self, from: data)

        #expect(decoded.provider == .eduVulcan)
        guard case let .eduVulcan(restored) = decoded.session else {
            Issue.record("Expected an eduVULCAN session")
            return
        }
        #expect(restored.tenant == "opole")
        #expect(restored.credential.fingerprint == "fp")
    }

    @Test("A portal-child Librus session keeps its bridge state")
    func portalSessionRoundTrip() throws {
        let state = LibrusPortalState(
            email: "parent@example.com",
            password: "secret",
            accountID: 42,
            accountLogin: "1234567u",
            portalAccessToken: "portal-token",
            portalRefreshToken: "refresh-token",
            portalExpiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            childAccessToken: "child-token",
            childExpiresAt: Date(timeIntervalSince1970: 1_890_000_000)
        )
        let session = LibrusSession(
            login: "parent@example.com",
            password: "secret",
            cookies: [
                LibrusCookie(
                    name: "DZIENNIKSID",
                    value: "sid",
                    domain: "synergia.librus.pl",
                    path: "/",
                    expiresAt: nil,
                    isSecure: true,
                    isHTTPOnly: true
                )
            ],
            loggedInAt: Date(timeIntervalSince1970: 1_800_000_000),
            loginCount: 1,
            lastRefreshAt: nil,
            lastRefreshFailedAt: nil,
            authMethod: .portal,
            portal: state
        )
        let student = RegistryStudent(
            id: "librus-42",
            provider: .librus,
            account: account(),
            session: .librus(session),
            isEnabled: true
        )

        let data = try JSONEncoder().encode(student)
        let decoded = try JSONDecoder().decode(RegistryStudent.self, from: data)

        guard case let .librus(restored) = decoded.session else {
            Issue.record("Expected a Librus session")
            return
        }
        #expect(restored.method == .portal)
        #expect(restored.portal?.accountLogin == "1234567u")
        #expect(restored.portal?.childAccessToken == "child-token")
        #expect(restored.portal?.portalRefreshToken == "refresh-token")
    }

    @Test("A session written before the portal fields existed still decodes")
    func legacyLibrusSessionDecodes() throws {
        let json = """
        {"login":"user@example.com","cookies":[],"loggedInAt":0,"loginCount":1}
        """
        let session = try JSONDecoder().decode(LibrusSession.self, from: Data(json.utf8))
        #expect(session.method == .web)
        #expect(session.portal == nil)
    }

    @Test("Legacy StoredStudent entries map to eduVULCAN without losing fields")
    func legacyMigration() {        let credential = HebeCredential(
            type: "RSA",
            restUrl: "https://example.invalid/api",
            certificate: "cert",
            privateKey: "key",
            fingerprint: "fp",
            deviceId: "device",
            deviceOs: "iOS",
            deviceModel: "iPhone",
            notificationToken: nil
        )
        let legacy = StoredStudent(
            id: "legacy-id",
            account: account(),
            credential: credential,
            restUrl: "https://example.invalid/api",
            login: "login",
            password: "password",
            tenant: "tenant",
            isEnabled: true
        )

        let mapped = RegistryStudent(legacy: legacy)
        #expect(mapped.id == "legacy-id")
        #expect(mapped.provider == .eduVulcan)
        guard case let .eduVulcan(session) = mapped.session else {
            Issue.record("Expected an eduVULCAN session")
            return
        }
        #expect(session.login == "login")
        #expect(session.password == "password")
        #expect(session.restURL == "https://example.invalid/api")
    }
}
