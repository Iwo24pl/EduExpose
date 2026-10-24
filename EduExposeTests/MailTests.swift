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

    @Test("Finds hiddenform by name even without WS-Fed fields")
    func findsHiddenformByName() throws {
        let html = """
        <form action="/login" method="post">
          <input type="hidden" name="UserName" value="">
        </form>
        <form name="hiddenform" action="https://uczen.eduvulcan.pl/krakow/Start" method="post">
          <input type="hidden" name="wa" value="wsignin1.0">
        </form>
        """
        let form = try #require(HTMLForm.hiddenform(in: html))

        #expect(form.action == "https://uczen.eduvulcan.pl/krakow/Start")
    }

    @Test("Ignores tag names that merely start with <form or <input")
    func ignoresLongerTagNames() throws {
        let html = """
        <formdata action="/no"><inputx type="hidden" name="x" value="1"></formdata>
        <form action="/yes"><input type="hidden" name="kept" value="1"><inputx type="hidden" name="dropped" value="2"></form>
        """

        let form = try #require(HTMLForm.first(in: html))

        #expect(form.action == "/yes")
        #expect(form.fields.map(\.name) == ["kept"])
    }
}

struct WSFedFormTests {
    /// The live `fs/ls` page escapes `<` and `"` but leaves `>` raw inside the
    /// SAML token, so the value's closing quote sits kilobytes past the first `>`.
    private let token = """
    &lt;trust:RequestSecurityTokenResponseCollection xmlns:trust=&quot;http://docs.oasis-open.org/ws-sx/ws-trust/200512&quot;>&lt;trust:RequestSecurityTokenResponse Context=&quot;nslo=1&quot;>&lt;saml:Assertion MajorVersion=&quot;1&quot; AssertionID=&quot;_abc-123&quot; Issuer=&quot;PrometeuszSecurityTokenService&quot; xmlns:saml=&quot;urn:oasis:names:tc:SAML:1.0:assertion&quot;>&lt;saml:Conditions>&lt;/saml:Conditions>&lt;/saml:Assertion>&lt;/trust:RequestSecurityTokenResponse>&lt;/trust:RequestSecurityTokenResponseCollection>
    """

    private var page: String {
        """
        <html><head><title>Working...</title></head><body>
        <form method="POST" name="hiddenform" action="https://dziennik-logowanie.vulcan.net.pl/katowice/Fs/Ls?wa=wsignin1.0">
        <input type="hidden" name="wa" value="wsignin1.0" />
        <input type="hidden" name="wresult" value="\(token)" />
        <input type="hidden" name="wctx" value="nslo=1" />
        </form></body></html>
        """
    }

    @Test("Reads the WS-Fed token even though its value contains a raw '>'")
    func readsTokenWithRawGreaterThan() throws {
        let form = try #require(HTMLForm.sso(in: page))

        #expect(form.name == "hiddenform")
        #expect(form.fields.count == 3)
        let wresult = try #require(form.fields.first { $0.name == "wresult" })
        #expect(wresult.value.hasPrefix("<trust:RequestSecurityTokenResponseCollection"))
        #expect(wresult.value.hasSuffix("</trust:RequestSecurityTokenResponseCollection>"))
        #expect(wresult.value.contains("<saml:Assertion"))
    }

    @Test("Posts the decoded token exactly like a browser")
    func postsDecodedToken() throws {
        let form = try #require(HTMLForm.sso(in: page))
        let body = String(decoding: form.body, as: UTF8.self)

        #expect(body.contains("wa=wsignin1.0"))
        #expect(body.contains("wctx=nslo%3D1"))
        #expect(body.contains("wresult=%3Ctrust%3ARequestSecurityTokenResponseCollection"))
        #expect(body.contains("Context%3D%22nslo%3D1%22"))
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

struct JournalLinkTests {
    private let portalHome = """
    <div class="connected-accounts">
      <a href="/dziennik/NB2HI4DT"><span class="connected-account-name">Jan Kowalski</span><span>SP 1</span></a>
      <a href="https://eduvulcan.pl/dziennik/ZZZ"><span class="connected-account-name">Anna Kowalska</span></a>
    </div>
    """

    @Test("Finds the portal journal tiles and picks the pupil")
    func picksJournalForPupil() throws {
        let base = try #require(URL(string: "https://eduvulcan.pl/"))
        let tiles = PrometheusMailClient.journalTiles(in: portalHome, relativeTo: base)

        #expect(tiles.count == 2)
        let picked = try #require(
            PrometheusMailClient.pickJournal(tiles, firstName: "Jan", surname: "Kowalski")
        )
        #expect(picked.url.absoluteString == "https://eduvulcan.pl/dziennik/NB2HI4DT")
        #expect(picked.name.contains("Jan Kowalski"))
    }

    @Test("Uses the only tile when the name does not match")
    func fallsBackToSingleTile() throws {
        let base = try #require(URL(string: "https://eduvulcan.pl/"))
        let html = #"<a href="/dziennik/ONE"><span class="connected-account-name">Someone Else</span></a>"#
        let tiles = PrometheusMailClient.journalTiles(in: html, relativeTo: base)
        let picked = try #require(
            PrometheusMailClient.pickJournal(tiles, firstName: "Jan", surname: "Kowalski")
        )

        #expect(picked.url.absoluteString == "https://eduvulcan.pl/dziennik/ONE")
    }

    @Test("Does not guess when several tiles and none match")
    func refusesAmbiguousJournal() throws {
        let base = try #require(URL(string: "https://eduvulcan.pl/"))
        let tiles = PrometheusMailClient.journalTiles(in: portalHome, relativeTo: base)

        #expect(
            PrometheusMailClient.pickJournal(tiles, firstName: "Piotr", surname: "Nowak") == nil
        )
    }

    @Test("Ignores elements that only start with <a, such as <area>")
    func ignoresLongerAnchorTagNames() throws {
        let html = #"<area href="/dziennik/B"><a href="/dziennik/C"><span class="connected-account-name">Jan Kowalski</span></a>"#
        let base = try #require(URL(string: "https://eduvulcan.pl/"))
        let tiles = PrometheusMailClient.journalTiles(in: html, relativeTo: base)

        #expect(tiles.map(\.url.absoluteString) == ["https://eduvulcan.pl/dziennik/C"])
    }
}

struct MailTraceRedactionTests {
    @Test("Trace URLs keep the path but drop query values")
    func redactsURLQuery() throws {
        let url = try #require(
            URL(string: "https://eduvulcan.pl/logowanie?ReturnUrl=secret&wa=token")
        )
        let safe = MailTraceRedaction.safeURL(url)

        #expect(safe.contains("/logowanie"))
        #expect(!safe.contains("secret"))
        #expect(!safe.contains("token"))
        #expect(safe.contains("[ReturnUrl,wa]"))
    }

    @Test("Trace snippets do not expose session values")
    func redactsHTMLValues() {
        let head = MailTraceRedaction.htmlHead(
            "<script>antiForgeryToken: 'secret-token'; appGuid: 'secret-guid'</script>"
        )

        #expect(!head.contains("secret-token"))
        #expect(!head.contains("secret-guid"))
        #expect(head.contains("<redacted>"))
    }

    @Test("Detects a real WS-Fed token in a page")
    func detectsWresultToken() {
        let token = String(repeating: "A", count: 120)
        let html = "<form><input type=\"hidden\" name=\"wresult\" value=\"\(token)\"></form>"

        #expect(MailTraceRedaction.wresultShape(html).contains("longValue=true"))
    }

    @Test("Detects a tokenless WS-Fed placeholder")
    func detectsEmptyWresult() {
        let html = #"<form><input type="hidden" name="wresult" value=""></form>"#
        let shape = MailTraceRedaction.wresultShape(html)

        #expect(shape.contains("wresult=present"))
        #expect(shape.contains("longValue=false"))
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

    @Test("Resolves a relative mailbox URL against the diary page")
    func resolvesRelativeMailboxURL() throws {
        let html = """
        <script>var VParam = { antiForgeryToken: 't', appGuid: 'g',
          wiadomosciUrl: '/katowice/App' };</script>
        """
        let base = try #require(URL(string: "https://uczen.eduvulcan.pl/"))
        let metadata = MailSessionMetadata.parse(html, baseURL: base)

        #expect(
            metadata.wiadomosciURL?.absoluteString
                == "https://uczen.eduvulcan.pl/katowice/App"
        )
    }

    @Test("Parses VParam JSON including wiadomosciUrl")
    func readsVParamJSON() {
        let html = """
        <html><head><title>Uczeń</title></head><body>
        <script>var VParam = {"antiForgeryToken": "tok", "appGuid": "guid",
          "apiUrl": "https://uczen.eduvulcan.pl/krakow/api",
          "wiadomosciUrl": "https://wiadomosci.eduvulcan.pl/krakow/App"};</script>
        </body></html>
        """
        let metadata = MailSessionMetadata.parse(html)

        #expect(metadata.isComplete)
        #expect(metadata.wiadomosciURL?.absoluteString == "https://wiadomosci.eduvulcan.pl/krakow/App")
    }
}

// MARK: - Address book and deletion

struct MailContactTests {
    @Test("Decodes an address-book page and derives the display name")
    func decodesContacts() throws {
        let json = """
        [{"skrzynkaGlobalKey": "teacher-key", "nazwa": "Natalia Wrzesień - P - (SP 1)"}]
        """

        let contacts = try PrometheusMailClient.decodeContacts(
            Data(json.utf8),
            role: .employee
        )

        #expect(contacts.count == 1)
        #expect(contacts[0].globalKey == "teacher-key")
        #expect(contacts[0].role == .employee)
        #expect(contacts[0].displayName == "Natalia Wrzesień")
        #expect(contacts[0].school == "SP 1")
        #expect(contacts[0].detail == "SP 1")
    }

    @Test("Accepts the alternate key and name spellings")
    func decodesAlternateSpellings() throws {
        let json = #"[{"globalKey": "student-key", "name": "Jan Kowalski - U - (SP 2)"}]"#

        let contacts = try PrometheusMailClient.decodeContacts(
            Data(json.utf8),
            role: .student
        )

        #expect(contacts.first?.globalKey == "student-key")
        #expect(contacts.first?.displayName == "Jan Kowalski")
        #expect(contacts.first?.school == "SP 2")
    }

    @Test("Keeps the role in the contact identity")
    func keepsRoleInIdentity() {
        let employee = MailContact(
            globalKey: "same-key",
            name: "Jan Kowalski - P - (SP 1)",
            role: .employee
        )
        let parent = MailContact(
            globalKey: "same-key",
            name: "Jan Kowalski - R - (SP 1)",
            role: .guardian
        )

        #expect(employee.id != parent.id)
        #expect(MailContactRole.role(inName: parent.name) == .guardian)
        #expect(MailContactRole.role(inName: "Anna Nowak - O - (SP 1)") == .guardian)
    }

    @Test("Groups the directories under Polish titles")
    func groupsByRole() {
        #expect(
            MailContactRole.allCases.map(\.groupTitle)
                == ["Nauczyciele", "Rodzice", "Uczniowie"]
        )
    }

    @Test("Picks the pupil's own mailbox for the default sender")
    func picksPupilMailbox() {
        let boxes = [
            Mailbox(globalKey: "parent", name: "Anna Kowalska - R - (SP 1)", type: 2),
            Mailbox(globalKey: "pupil", name: "Jan Kowalski - U - (SP 1)", type: 1)
        ]

        let match = VulcanMailboxName.bestMatch(
            in: boxes,
            firstName: "Jan",
            surname: "Kowalski"
        )

        #expect(match?.globalKey == "pupil")
    }

    @Test("Decodes the reply participants with their mailbox keys")
    func decodesReplyParticipants() throws {
        let json = """
        {"nadawcaSkrzynkaGlobalKey": "sender-key",
         "nadawcaSkrzynkaNazwa": "Natalia Wrzesień - P - (SP 1)",
         "adresaci": [
           {"skrzynkaGlobalKey": "parent-key", "nazwa": "Anna Kowalska - R - (SP 1)"}
         ]}
        """

        let dto = try JSONDecoder().decode(
            PrometheusReplyDTO.self,
            from: Data(json.utf8)
        )

        #expect(dto.nadawcaSkrzynkaGlobalKey == "sender-key")
        #expect(dto.adresaci?.first?.skrzynkaGlobalKey == "parent-key")
    }
}

struct MailDeletionTests {
    @Test("Moves to trash first and deletes permanently only from the trash")
    func choosesDeleteEndpoint() {
        #expect(PrometheusDeletion.endpoint(permanently: false) == "MoveTrash")
        #expect(PrometheusDeletion.endpoint(permanently: true) == "Delete")
    }

    @Test("Sends the message keys as a JSON array")
    func encodesDeleteBody() throws {
        let data = try PrometheusDeletion.body(id: "abc")
        let keys = try JSONSerialization.jsonObject(with: data) as? [String]

        #expect(keys == ["abc"])
    }
}
