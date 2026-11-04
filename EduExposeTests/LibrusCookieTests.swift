import Foundation
import Testing
@testable import EduExpose

@Suite("Librus cookies")
struct LibrusCookieTests {
    private let networkURL = URL(string: "https://synergia.librus.pl/gateway/api/2.0/Me")!
    private let oauthURL = URL(string: "https://api.librus.pl/OAuth/Authorization?client_id=46")!
    private let rootURL = URL(string: "https://api.librus.pl/")!

    @Test("Parses the session cookie")
    func parsesSessionCookie() throws {
        let cookie = try #require(LibrusCookie.parse(
            "oauth_token=abc123; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly",
            for: networkURL
        ))

        #expect(cookie.name == "oauth_token")
        #expect(cookie.value == "abc123")
        #expect(cookie.domain == "synergia.librus.pl")
        #expect(cookie.path == "/")
        #expect(cookie.isSecure)
        #expect(cookie.isHTTPOnly)
        #expect(cookie.matches(networkURL))
    }

    @Test("Keeps the DeviceCookie path at /OAuth")
    func keepsDeviceCookiePath() throws {
        let cookie = try #require(LibrusCookie.parse(
            "DeviceCookie=xyz; Domain=api.librus.pl; Path=/OAuth; Max-Age=31536000; Secure",
            for: oauthURL
        ))

        #expect(cookie.path == "/OAuth")
        #expect(cookie.matches(oauthURL))
        #expect(!cookie.matches(rootURL))
    }

    @Test("Splits combined Set-Cookie headers without breaking Expires")
    func splitsCombinedHeaders() {
        let parts = LibrusCookie.splitCombined(
            "a=1; Expires=Wed, 09 Jun 2026 10:18:14 GMT; Path=/, b=2; Path=/api"
        )
        #expect(parts.count == 2)
        #expect(parts[0].hasPrefix("a=1"))
        #expect(parts[1].hasPrefix("b=2"))
    }

    @Test("The jar scopes cookies by host and path")
    func jarScopesCookies() async {
        let jar = LibrusCookieJar()
        await jar.store([
            "oauth_token=abc; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly",
            "DeviceCookie=xyz; Domain=api.librus.pl; Path=/OAuth; Max-Age=31536000; Secure"
        ], for: oauthURL)

        let oauthHeader = await jar.header(for: oauthURL)
        let rootHeader = await jar.header(for: rootURL)
        let networkHeader = await jar.header(for: networkURL)

        #expect(oauthHeader?.contains("DeviceCookie=xyz") == true)
        #expect(rootHeader == nil)
        #expect(networkHeader?.contains("oauth_token=abc") == true)
        #expect(networkHeader?.contains("DeviceCookie") != true)
    }

    @Test("Only allowlisted cookies are persisted")
    func persistsAllowlist() async {
        let jar = LibrusCookieJar()
        await jar.store([
            "oauth_token=abc; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly",
            "DZIENNIKSID=def; Domain=synergia.librus.pl; Path=/",
            "random=value; Domain=synergia.librus.pl; Path=/",
            "DeviceCookie=xyz; Domain=api.librus.pl; Path=/OAuth; Max-Age=31536000; Secure"
        ], for: networkURL)

        let persisted = await jar.snapshotPersistable()
        let names = Set(persisted.map(\.name))

        #expect(names.contains("oauth_token"))
        #expect(names.contains("DZIENNIKSID"))
        #expect(names.contains("DeviceCookie"))
        #expect(!names.contains("random"))
    }

    @Test("Expired cookies are dropped")
    func dropsExpired() async {
        let jar = LibrusCookieJar()
        let url = URL(string: "https://synergia.librus.pl/")!
        await jar.store(
            ["oauth_token=old; Domain=synergia.librus.pl; Path=/; Max-Age=0"],
            for: url
        )
        let header = await jar.header(for: url)
        #expect(header == nil)
    }

    @Test("A cookie domain matches its subdomains only")
    func domainMatching() {
        let cookie = LibrusCookie(
            name: "a",
            value: "1",
            domain: "librus.pl",
            path: "/",
            expiresAt: nil,
            isSecure: false,
            isHTTPOnly: false
        )
        #expect(cookie.matches(URL(string: "https://synergia.librus.pl/")!))
        #expect(cookie.matches(URL(string: "https://api.librus.pl/")!))
        #expect(!cookie.matches(URL(string: "https://evil.example/")!))
    }
}
