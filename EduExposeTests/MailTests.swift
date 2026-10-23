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
    @Test("Recreates a cookie for the requested host")
    func recreatesCookieForHost() throws {
        let original = try #require(HTTPCookie(properties: [
            .name: "auth",
            .value: "token",
            .domain: "eduvulcan.pl",
            .path: "/"
        ]))
        let snapshot = CookieSnapshot(cookie: original)
        let copy = try #require(snapshot.cookie(for: "wiadomosci.eduvulcan.pl"))

        #expect(copy.name == "auth")
        #expect(copy.value == "token")
        #expect(copy.domain.contains("wiadomosci.eduvulcan.pl"))
    }
}
