import Foundation
import Testing

@testable import EduExpose

struct LoginPageParsingTests {
    private let sample = #"""
    <form action="/logowanie" method="post">
        <div class="captcha-wrapper input-components" data-challenge="5e2973d8" data-difficulty="100000" data-rounds="15">
            <input id="captcha-response" name="captcha-response" type="hidden">
        </div>
        <input name="__RequestVerificationToken" type="hidden" value="QQZrwIC83_vUOP7vmwFLCleE" />
    </form>
    """#

    @Test("Reads the anti-forgery token from the hidden input")
    func readsCsrfToken() {
        #expect(LoginPage.csrfToken(in: sample) == "QQZrwIC83_vUOP7vmwFLCleE")
    }

    @Test("Reads the anti-forgery token when value comes before name")
    func readsReorderedToken() {
        let html = #"<input type='hidden' value='abc-123' name='__RequestVerificationToken'>"#
        #expect(LoginPage.csrfToken(in: html) == "abc-123")
    }

    @Test("Ignores a page that is not the login form")
    func ignoresOtherPages() {
        #expect(LoginPage.csrfToken(in: "<html><body><h1>404</h1></body></html>") == nil)
        #expect(LoginPage.csrfToken(in: #"<input name="UserName" value="jan" />"#) == nil)
    }

    @Test("Reads the captcha challenge")
    func readsCaptcha() throws {
        let captcha = try #require(LoginPage.captcha(in: sample))
        #expect(captcha.challenge == "5e2973d8")
        #expect(captcha.difficulty == 100_000)
        #expect(captcha.rounds == 15)
    }

    @Test("Returns no captcha when the wrapper is absent")
    func missingCaptcha() {
        #expect(LoginPage.captcha(in: "<div class=\"login-box\"></div>") == nil)
    }

    @Test("Reads ShowCaptcha from the object payload")
    func showCaptchaObject() {
        let data = Data(#"{"success":true,"data":{"ShowCaptcha":true,"ExtraMessage":""}}"#.utf8)
        let disabled = Data(#"{"success":true,"data":{"ShowCaptcha":false}}"#.utf8)
        #expect(LoginPage.showCaptcha(in: data) == true)
        #expect(LoginPage.showCaptcha(in: disabled) == false)
    }

    @Test("Ignores malformed QueryUserInfo responses")
    func showCaptchaFallback() {
        #expect(LoginPage.showCaptcha(in: Data(#"{"success":true,"data":true}"#.utf8)) == nil)
        #expect(LoginPage.showCaptcha(in: Data("not json".utf8)) == nil)
        #expect(LoginPage.showCaptcha(in: Data()) == nil)
    }

    @Test("Detects the captcha rejection, not the captcha label")
    func captchaRejection() {
        let rejection = "Poczekaj przed przejściem dalej, aż sprawdzanie zabezpieczenia przed robotami osiągnie 100%."
        let normalPage = "<label>Zabezpieczenie przed robotami - proszę czekać</label>"
        #expect(LoginPage.isCaptchaRejection(rejection))
        #expect(!LoginPage.isCaptchaRejection(normalPage))
    }

    @Test("Reads the #ap payload from /api/ap")
    func readsApiApPayload() {
        let html = #"<input id="ap" type="hidden" value="{&quot;Success&quot;:true}" />"#
        let tag = LoginPage.firstMatch(html, #"<input[^>]*\bid\s*=\s*(?:"ap"|'ap'|ap\b)[^>]*>"#)?.first
        #expect(LoginPage.attribute(tag ?? "", "value") == "{&quot;Success&quot;:true}")
    }
}
