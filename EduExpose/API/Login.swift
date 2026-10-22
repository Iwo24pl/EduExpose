import Foundation
import CryptoKit

enum LoginError: LocalizedError {
    case csrf
    case captcha
    case invalidCredentials
    case emailNotConfirmed
    case api(String)
    case noAccounts

    var errorDescription: String? {
        switch self {
        case .csrf: return "Nie udało się odczytać tokenu logowania. Spróbuj ponownie."
        case .captcha: return "Weryfikacja captchy nie powiodła się. Spróbuj ponownie."
        case .invalidCredentials: return "Nieprawidłowy login lub hasło."
        case .emailNotConfirmed: return "Twój adres e-mail nie został jeszcze potwierdzony."
        case .api(let message): return message
        case .noAccounts: return "Nie znaleziono kont uczniów dla tego loginu."
        }
    }
}

struct ApiApResponse: Decodable {
    let success: Bool
    let tokens: [String]
    let accessToken: String
    let isConsentAccepted: Bool
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case success = "Success"
        case tokens = "Tokens"
        case accessToken = "AccessToken"
        case isConsentAccepted = "IsConsentAccepted"
        case errorMessage = "ErrorMessage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        tokens = (try? container.decode([String].self, forKey: .tokens)) ?? []
        accessToken = (try? container.decode(String.self, forKey: .accessToken)) ?? ""
        isConsentAccepted = (try? container.decode(Bool.self, forKey: .isConsentAccepted)) ?? true
        errorMessage = try? container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

struct JwtPayload: Decodable {
    let tenant: String
}

/// Signs in through the eduVULCAN web portal and registers Hebe CE devices.
struct PrometheusLoginService {
    let session: URLSession
    private let base = "https://eduvulcan.pl"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"

    init(session: URLSession) {
        self.session = session
    }

    func signIn(login: String, password: String) async throws -> [StoredStudent] {
        let showCaptcha = await queryUserInfo(login)
        let html = try await loginPage()
        if html.contains("Twój adres e-mail nie został jeszcze potwierdzony.") {
            throw LoginError.emailNotConfirmed
        }

        guard let csrfTag = firstMatch(html, "<input[^>]*name=\"__RequestVerificationToken\"[^>]*>")?.first,
              let csrf = attribute(csrfTag, "value") else {
            throw LoginError.csrf
        }

        var captcha = ""
        if showCaptcha {
            guard let wrapper = firstMatch(html, "<div[^>]*class=\"[^\"]*captcha-wrapper[^\"]*\"[^>]*>")?.first,
                  let challenge = attribute(wrapper, "data-challenge"),
                  let difficultyText = attribute(wrapper, "data-difficulty"),
                  let difficulty = UInt32(difficultyText),
                  let roundsText = attribute(wrapper, "data-rounds"),
                  let rounds = Int(roundsText) else {
                throw LoginError.captcha
            }
            captcha = captchaResponse(challenge: challenge, difficulty: difficulty, rounds: rounds)
        }

        try await postLogin(login: login, password: password, csrf: csrf, captcha: captcha)
        let apiAp = try await apiApWithConsent()

        guard apiAp.success else {
            throw LoginError.api(apiAp.errorMessage ?? "API /api/ap zwróciło błąd.")
        }
        guard !apiAp.tokens.isEmpty else {
            throw LoginError.noAccounts
        }

        var grouped: [String: [String]] = [:]
        for token in apiAp.tokens {
            let tenant = (try? decodeJWT(token).tenant) ?? "eduvulcan"
            grouped[tenant, default: []].append(token)
        }

        var result: [StoredStudent] = []
        for (tenant, tokens) in grouped {
            var credential = try Signing.makeCredential()
            let client = HebeClient(credential: credential, session: session)
            credential = try await client.registerJWT(tokens: tokens, tenant: tenant)
            let accounts = try await client.accounts()
            for account in accounts {
                result.append(StoredStudent(
                    id: account.id,
                    account: account,
                    credential: credential,
                    restUrl: credential.restUrl ?? "",
                    login: login,
                    password: password,
                    tenant: tenant,
                    isEnabled: true
                ))
            }
        }

        guard !result.isEmpty else {
            throw LoginError.noAccounts
        }
        return result.sorted { $0.account.displayName < $1.account.displayName }
    }

    // MARK: Portal steps

    private func queryUserInfo(_ login: String) async -> Bool {
        guard let url = URL(string: base + "/Account/QueryUserInfo") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody([("UserName", login)])
        let result = try? await session.data(for: request)
        guard let data = result?.0 else { return false }
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any],
              let payload = object["data"] as? [String: Any] else {
            return false
        }
        if let flag = payload["ShowCaptcha"] as? Bool { return flag }
        if let text = payload["ShowCaptcha"] as? String { return text.lowercased() == "true" }
        return false
    }

    private func loginPage() async throws -> String {
        guard let url = URL(string: base + "/logowanie") else {
            throw LoginError.api("Nieprawidłowy adres logowania.")
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    private func postLogin(login: String, password: String, csrf: String, captcha: String) async throws {
        guard let url = URL(string: base + "/logowanie") else {
            throw LoginError.api("Nieprawidłowy adres logowania.")
        }
        let configuration = session.configuration
        let noRedirectSession = URLSession(
            configuration: configuration,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { noRedirectSession.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody([
            ("UserName", login),
            ("Password", password),
            ("captcha-response", captcha),
            ("__RequestVerificationToken", csrf)
        ])

        let (data, response) = try await noRedirectSession.data(for: request)
        let body = String(decoding: data, as: UTF8.self)
        if body.contains("Twój adres e-mail nie został jeszcze potwierdzony.") {
            throw LoginError.emailNotConfirmed
        }
        let lowered = body.lowercased()
        if lowered.contains("robot") || lowered.contains("robak") {
            throw LoginError.captcha
        }
        guard let http = response as? HTTPURLResponse else {
            throw LoginError.api("Serwer nie odpowiedział.")
        }
        guard http.value(forHTTPHeaderField: "Location") != nil else {
            throw LoginError.invalidCredentials
        }
    }

    private func apiApWithConsent() async throws -> ApiApResponse {
        let initial = try await apiAp(accessToken: nil)
        if initial.isConsentAccepted {
            return initial
        }
        try await acceptConsent(accessToken: initial.accessToken.isEmpty ? nil : initial.accessToken)
        let refreshed = try await apiAp(accessToken: initial.accessToken.isEmpty ? nil : initial.accessToken)
        guard refreshed.isConsentAccepted else {
            throw LoginError.api(refreshed.errorMessage ?? "Nie udało się zaakceptować regulaminu.")
        }
        return refreshed
    }

    private func apiAp(accessToken: String?) async throws -> ApiApResponse {
        guard let url = URL(string: base + "/api/ap") else {
            throw LoginError.api("Nieprawidłowy adres API.")
        }
        var request = URLRequest(url: url)
        request.setValue("Dart/3.11 (dart:io)", forHTTPHeaderField: "user-agent")
        request.setValue("1", forHTTPHeaderField: "vapi")
        request.setValue("api%2fap", forHTTPHeaderField: "vcanonicalurl")
        request.setValue("Android", forHTTPHeaderField: "vos")
        request.setValue("998", forHTTPHeaderField: "vversioncode")
        request.setValue(Signing.signatureDate(), forHTTPHeaderField: "vdate")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await session.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        return try decodeApiAp(html)
    }

    private func acceptConsent(accessToken: String?) async throws {
        guard let url = URL(string: base + "/konto/zgody") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = formBody([
            ("HasUnacceptedOnlyOneRegulation", "true"),
            ("Consent[0].Key", "6"),
            ("Consent[0].Value", "true")
        ])
        _ = try await session.data(for: request)
    }

    // MARK: Decoding

    private func decodeApiAp(_ html: String) throws -> ApiApResponse {
        guard let tag = firstMatch(html, "<input[^>]*id=\"ap\"[^>]*>")?.first,
              let raw = attribute(tag, "value") else {
            throw LoginError.api("Nie znaleziono danych logowania w odpowiedzi /api/ap.")
        }
        guard let data = raw.htmlUnescaped.data(using: .utf8) else {
            throw LoginError.api("Nie udało się odczytać danych logowania.")
        }
        do {
            return try JSONDecoder().decode(ApiApResponse.self, from: data)
        } catch {
            throw LoginError.api("Nieoczekiwany format odpowiedzi logowania.")
        }
    }

    private func decodeJWT(_ token: String) throws -> JwtPayload {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw LoginError.api("Nieprawidłowy token ucznia.")
        }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        guard let data = Data(base64Encoded: base64) else {
            throw LoginError.api("Nieprawidłowy token ucznia.")
        }
        do {
            return try JSONDecoder().decode(JwtPayload.self, from: data)
        } catch {
            throw LoginError.api("Token ucznia nie zawiera szkoły.")
        }
    }

    // MARK: Proof of work captcha

    private func captchaResponse(challenge: String, difficulty: UInt32, rounds: Int) -> String {
        guard difficulty > 0, rounds > 0 else { return "" }
        var buffer = Array(challenge.utf8)
        var answers: [String] = []

        for _ in 0..<rounds {
            var nonce: UInt64 = 1
            var solved = false
            while nonce < 50_000_000 {
                let digits = Array(String(nonce).utf8)
                let candidate = buffer + digits
                let digest = Array(SHA256.hash(data: candidate))
                let value = (UInt32(digest[0]) << 24)
                    | (UInt32(digest[1]) << 16)
                    | (UInt32(digest[2]) << 8)
                    | UInt32(digest[3])
                if value < difficulty {
                    answers.append(String(nonce))
                    buffer = candidate
                    solved = true
                    break
                }
                nonce += 1
            }
            if !solved { break }
        }
        return answers.joined(separator: ";")
    }

    // MARK: Tiny HTML helpers

    private func formBody(_ pairs: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func firstMatch(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : nsText.substring(with: range))
        }
        return groups
    }

    private func attribute(_ tag: String, _ name: String) -> String? {
        let pattern = name + "=\"([^\"]*)\""
        return firstMatch(tag, pattern)?[1]
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension String {
    var htmlUnescaped: String {
        var text = self
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#34;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&#x2F;", with: "/")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text
    }
}
