import Foundation
import Testing
@testable import EduExpose

struct VulcanMailboxNameTests {
    @Test("Parses the school mailbox format")
    func parsesSchoolMailbox() throws {
        let parsed = try #require(
            VulcanMailboxName.parse("Szkoła Podstawowa nr 1 [sp1] - O - (SP 1)")
        )

        #expect(parsed.name == "Szkoła Podstawowa nr 1")
        #expect(parsed.code == "sp1")
        #expect(parsed.role == "O")
        #expect(parsed.studentName == nil)
        #expect(parsed.shortSchoolName == "SP 1")
    }

    @Test("Parses the student mailbox format")
    func parsesStudentMailbox() throws {
        let parsed = try #require(
            VulcanMailboxName.parse("SP 1 - O - Jan Kowalski - (SP 1)")
        )

        #expect(parsed.name == "SP 1")
        #expect(parsed.studentName == "Jan Kowalski")
        #expect(parsed.shortSchoolName == "SP 1")
    }

    @Test("Matches a mailbox to a pupil")
    func matchesPupil() throws {
        let parsed = try #require(
            VulcanMailboxName.parse("SP 1 - O - Jan Kowalski - (SP 1)")
        )

        #expect(parsed.matches(firstName: "Jan", surname: "Kowalski"))
        #expect(!parsed.matches(firstName: "Anna", surname: "Kowalska"))
    }

    @Test("Rejects an unrecognised mailbox name")
    func rejectsUnknownFormat() {
        #expect(VulcanMailboxName.parse("Skrzynka") == nil)
        #expect(VulcanMailboxName.parse(" - O - (SP 1)") == nil)
    }

    @Test("Does not match a pupil whose name only shares a prefix")
    func doesNotMatchNamePrefix() throws {
        let parsed = try #require(
            VulcanMailboxName.parse("SP 1 - O - Janina Kowalska - (SP 1)")
        )

        #expect(!parsed.matches(firstName: "Jan", surname: "Kowalski"))
    }
}

struct MailTextTests {
    @Test("Strips HTML and keeps paragraph breaks")
    func stripsHTML() {
        let text = MailText.plainText(
            from: "<p>Dzień dobry,</p><p>to jest <strong>test</strong>.<br>Pozdrawiam</p>"
        )

        #expect(text == "Dzień dobry,\n\nto jest test.\nPozdrawiam")
    }

    @Test("Decodes common HTML entities")
    func decodesEntities() {
        #expect(MailText.plainText(from: "A &amp; B &lt; C &gt; D &quot;E&quot;") == "A & B < C > D \"E\"")
    }

    @Test("Decodes numeric entities")
    func decodesNumericEntities() {
        #expect(MailText.plainText(from: "It&#39;s &#x27;fine&#x27;") == "It's 'fine'")
    }

    @Test("Drops script and style contents")
    func dropsScriptAndStyle() {
        let html = """
        <style>p { color: red; }</style>
        <p>Dzień dobry</p>
        <script>alert('x')</script>
        """
        #expect(MailText.plainText(from: html) == "Dzień dobry")
    }
}

struct HTMLFormTests {
    @Test("Reads the action and hidden inputs")
    func readsForm() throws {
        let html = """
        <html><body>
        <form method="post" action="/sso/continue">
          <input type="hidden" name="wa" value="wsignin1.0">
          <input type="hidden" name="wctx" value="auth=studentEV&amp;nslo=1">
          <input type="text" name="ignored" value="x">
          <button type="submit">Dalej</button>
        </form>
        </body></html>
        """

        let form = try #require(HTMLForm.first(in: html))

        #expect(form.action == "/sso/continue")
        #expect(form.fields.count == 2)
        #expect(form.fields[0].name == "wa")
        #expect(form.fields[0].value == "wsignin1.0")
        #expect(form.fields[1].name == "wctx")
        #expect(form.fields[1].value == "auth=studentEV&nslo=1")
    }

    @Test("Resolves a relative action")
    func resolvesRelativeAction() throws {
        let html = #"<form action="/Account/Login"><input type="hidden" name="x" value="1"></form>"#
        let form = try #require(HTMLForm.first(in: html))
        let url = try #require(form.url(relativeTo: URL(string: "https://eduvulcan.pl/fs/ls")!))

        #expect(url.absoluteString == "https://eduvulcan.pl/Account/Login")
    }

    @Test("An empty action posts back to the current page")
    func emptyActionUsesCurrentPage() throws {
        let html = #"<form action="" method="post"><input type="hidden" name="x" value="1"></form>"#
        let form = try #require(HTMLForm.first(in: html))
        let base = try #require(URL(string: "https://eduvulcan.pl/fs/ls?wa=wsignin1.0"))
        let url = try #require(form.url(relativeTo: base))

        #expect(url.absoluteString == base.absoluteString)
    }

    @Test("Picks the WS-Federation form instead of the first form")
    func findsSSOForm() throws {
        let html = """
        <form action="/login" method="post">
          <input type="hidden" name="UserName" value="">
        </form>
        <form name="hiddenform" action="https://wiadomosci.eduvulcan.pl/krakow/Account/Login" method="post">
          <input type="hidden" name="wa" value="wsignin1.0">
          <input type="hidden" name="wresult" value="token">
          <input type="hidden" name="wctx" value="ctx">
        </form>
        """
        let form = try #require(HTMLForm.sso(in: html))

        #expect(form.action == "https://wiadomosci.eduvulcan.pl/krakow/Account/Login")
        #expect(form.fields.count == 3)
    }

    @Test("Encodes form bodies without losing plus signs")
    func encodesFormBody() throws {
        let html = #"<form action="/sso"><input type="hidden" name="wresult" value="a+b c/d=="></form>"#
        let form = try #require(HTMLForm.first(in: html))
        let body = String(decoding: form.body, as: UTF8.self)

        #expect(body == "wresult=a%2Bb+c%2Fd%3D%3D")
    }

    @Test("Encodes non-ASCII form values as UTF-8")
    func encodesUnicodeFormBody() {
        #expect(FormURLEncoding.encode([("q", "ąć +")]) == "q=%C4%85%C4%87+%2B")
    }

    @Test("Decodes numeric entities in hidden inputs")
    func decodesNumericEntitiesInFields() throws {
        let html = #"<form action="/x"><input type="hidden" name="v" value="&#x27;a&#39;b"></form>"#
        let form = try #require(HTMLForm.first(in: html))

        #expect(form.fields.first?.value == "'a'b")
    }
}

struct PrometheusPayloadTests {
    @Test("Decodes the message list payload")
    func decodesMessageList() throws {
        let json = """
        [{
          "apiGlobalKey": "abc",
          "data": "2026-10-23T08:15:00Z",
          "id": 42,
          "przeczytana": false,
          "hasZalaczniki": true,
          "temat": "Wyjście do teatru",
          "korespondenci": "Jan Kowalski"
        }]
        """

        let messages = try JSONDecoder().decode(
            [PrometheusMessageDTO].self,
            from: Data(json.utf8)
        )

        #expect(messages.count == 1)
        #expect(messages[0].apiGlobalKey == "abc")
        #expect(messages[0].temat == "Wyjście do teatru")
        #expect(messages[0].hasZalaczniki == true)
    }

    @Test("Encodes the send payload with the Prometheus keys")
    func encodesSendPayload() throws {
        let payload = PrometheusSendMessage(
            globalKey: "new",
            watekGlobalKey: "thread",
            nadawcaSkrzynkaGlobalKey: "own",
            adresaciSkrzynkiGlobalKeys: ["parent"],
            tytul: "Temat",
            tresc: "Treść",
            zalaczniki: [],
            powitalna: false,
            odpowiedziana: nil,
            przekazana: nil
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["globalKey"] as? String == "new")
        #expect(object["watekGlobalKey"] as? String == "thread")
        #expect(object["nadawcaSkrzynkaGlobalKey"] as? String == "own")
        #expect(object["adresaciSkrzynkiGlobalKeys"] as? [String] == ["parent"])
        #expect(object["powitalna"] as? Bool == false)
        #expect(object["odpowiedziana"] == nil)
    }
}

struct CookieSnapshotTests {
    @Test("Preserves the original cookie domain and path")
    func preservesCookieScope() throws {
        let original = try #require(HTTPCookie(properties: [
            .name: "auth",
            .value: "token",
            .domain: "eduvulcan.pl",
            .path: "/"
        ]))
        let snapshot = CookieSnapshot(cookie: original)
        let copy = try #require(snapshot.cookie)

        #expect(copy.name == "auth")
        #expect(copy.value == "token")
        #expect(copy.domain.contains("eduvulcan.pl"))
        #expect(copy.path == "/")
    }

    @Test("Captures only the portal's own cookies")
    func capturesPortalCookiesOnly() throws {
        let portal = try #require(HTTPCookie(properties: [
            .name: "portal", .value: "1", .domain: "eduvulcan.pl", .path: "/"
        ]))
        let staleMailbox = try #require(HTTPCookie(properties: [
            .name: "student", .value: "2", .domain: "uczen.eduvulcan.pl", .path: "/"
        ]))
        let unrelated = try #require(HTTPCookie(properties: [
            .name: "hebe", .value: "3", .domain: "lekcjaplus.vulcan.net.pl", .path: "/"
        ]))

        let captured = CookieSnapshot.capturePortal([portal, staleMailbox, unrelated])

        #expect(captured.map(\.name) == ["portal"])
    }
}

struct MailSessionMetadataTests {
    @Test("Reads tokens from the VParam object")
    func readsVParam() throws {
        let html = """
        <script>
        var VParam = { antiForgeryToken: 'token-value', appGuid: 'guid-value',
          apiUrl: 'https://wiadomosci.eduvulcan.pl/krakow/api' };
        </script>
        """
        let metadata = MailSessionMetadata.parse(html)

        #expect(metadata.isComplete)
        #expect(metadata.antiForgeryToken == "token-value")
        #expect(metadata.appGuid == "guid-value")
        #expect(metadata.apiURL?.absoluteString == "https://wiadomosci.eduvulcan.pl/krakow/api")
    }

    @Test("Accepts assignment syntax and double quotes")
    func readsAssignmentSyntax() {
        let html = #"appGuid = "guid-value"; antiForgeryToken = "token-value";"#
        let metadata = MailSessionMetadata.parse(html)

        #expect(metadata.isComplete)
        #expect(metadata.appGuid == "guid-value")
        #expect(metadata.antiForgeryToken == "token-value")
    }
}
