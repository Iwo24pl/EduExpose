import Foundation

// MARK: - API payloads

struct PrometheusMailboxDTO: Decodable, Sendable {
    let globalKey: String
    let nazwa: String
    let typUzytkownika: Int?
}

struct PrometheusMessageDTO: Decodable, Sendable {
    let apiGlobalKey: String
    let data: String
    let id: Int?
    let przeczytana: Bool?
    let hasZalaczniki: Bool?
    let temat: String?
    let korespondenci: String?
}

struct PrometheusAttachmentDTO: Decodable, Sendable {
    let url: String?
    let idZalacznik: Int?
    let nazwaPliku: String?
    let idOneDrive: String?
}

struct PrometheusMessageDetailsDTO: Decodable, Sendable {
    let apiGlobalKey: String
    let data: String?
    let id: Int?
    let odczytana: Bool?
    let temat: String?
    let odbiorcy: [String]?
    let nadawca: String?
    let tresc: String?
    let zalaczniki: [PrometheusAttachmentDTO]?
}

struct PrometheusSendMessage: Encodable, Sendable {
    let globalKey: String
    let watekGlobalKey: String
    let nadawcaSkrzynkaGlobalKey: String
    let adresaciSkrzynkiGlobalKeys: [String]
    let tytul: String
    let tresc: String
    let zalaczniki: [String]
    let powitalna: Bool
    let odpowiedziana: String?
    let przekazana: String?
}

// MARK: - Errors

enum PrometheusMailError: LocalizedError, Sendable {
    case missingCredentials
    case loginFailed
    case noMailbox
    case sessionExpired
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Zaloguj się ponownie, aby otworzyć wiadomości."
        case .loginFailed:
            return "Nie udało się zalogować do skrzynki wiadomości."
        case .noMailbox:
            return "To konto nie ma skrzynki wiadomości."
        case .sessionExpired:
            return "Sesja wiadomości wygasła. Spróbuj ponownie."
        case .invalidResponse:
            return "Serwer wiadomości zwrócił nieoczekiwaną odpowiedź."
        case .server(let message):
            return message
        }
    }
}

// MARK: - Prometheus mailbox client

/// Web-mailbox client for non-Hebe EduVulcan accounts.
///
/// The mailbox lives on `wiadomosci.eduvulcan.pl`; the Hebe `mobile/messages`
/// endpoints are an archive/fallback for units whose `restUrl` contains
/// `hebe`. This client follows the same SSO flow as the Kotlin reference.
actor PrometheusMailClient: MailService {
    private let tenant: String
    private let login: String
    private let password: String
    private let pupilFirstName: String
    private let pupilSurname: String
    private let session: URLSession
    private let initialCookies: [CookieSnapshot]

    private var isInitialized = false
    private var selectedMailbox: Mailbox?
    private var antiForgeryToken = ""
    private var appGuid = ""

    private let portalBase = URL(string: "https://eduvulcan.pl")!
    private let ssoBase = URL(string: "https://dziennik-logowanie.vulcan.net.pl")!
    private let messagesBase = URL(string: "https://wiadomosci.eduvulcan.pl")!
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"

    init(student: StoredStudent, session: URLSession, initialCookies: [CookieSnapshot]) {
        tenant = student.tenant ?? ""
        login = student.login ?? ""
        password = student.password ?? ""
        pupilFirstName = student.account.pupil.firstName
        pupilSurname = student.account.pupil.surname
        self.session = session
        self.initialCookies = initialCookies
    }

    // MARK: MailService

    func messages(kind: MessageKind) async throws -> [MailMessage] {
        let mailbox = try await resolveMailbox()
        let endpoint: String
        switch kind {
        case .received:
            endpoint = "/api/OdebraneSkrzynka"
        case .sent:
            endpoint = "/api/WyslaneSkrzynka"
        case .deleted:
            endpoint = "/api/UsunieteSkrzynka"
        }

        let data = try await apiRequest(
            path: "/\(tenant)\(endpoint)",
            query: [
                URLQueryItem(name: "globalKeySkrzynka", value: mailbox.globalKey),
                URLQueryItem(name: "idLastWiadomosc", value: "0"),
                URLQueryItem(name: "pageSize", value: "50")
            ]
        )
        let items = try decoder.decode([PrometheusMessageDTO].self, from: data)
        return items.map { item in
            MailMessage(
                id: item.apiGlobalKey,
                subject: item.temat?.nilIfEmpty ?? "(bez tematu)",
                correspondent: item.korespondenci?.nilIfEmpty ?? "Nieznany",
                date: item.data,
                isUnread: (item.przeczytana ?? false) == false,
                hasAttachments: item.hasZalaczniki == true,
                inlineBody: nil,
                inlineAttachments: []
            )
        }
        .sorted { $0.date > $1.date }
    }

    func detail(id: String) async throws -> MailMessageDetail {
        let data = try await apiRequest(
            path: "/\(tenant)/api/WiadomoscSzczegoly",
            query: [URLQueryItem(name: "apiGlobalKey", value: id)]
        )
        let item = try decoder.decode(PrometheusMessageDetailsDTO.self, from: data)
        let attachments = (item.zalaczniki ?? []).map { attachment in
            MailAttachment(
                id: attachment.idZalacznik.map { String($0) }
                    ?? attachment.idOneDrive
                    ?? attachment.url
                    ?? UUID().uuidString,
                name: attachment.nazwaPliku?.nilIfEmpty ?? "Załącznik",
                url: attachment.url.flatMap(Self.absoluteURL)
            )
        }
        return MailMessageDetail(
            id: item.apiGlobalKey,
            subject: item.temat?.nilIfEmpty ?? "(bez tematu)",
            sender: item.nadawca?.nilIfEmpty ?? "Nieznany",
            recipients: item.odbiorcy ?? [],
            date: item.data ?? "",
            body: MailText.plainText(from: item.tresc ?? ""),
            attachments: attachments
        )
    }

    func markRead(id: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["apiGlobalKey": id])
        _ = try await apiRequest(
            path: "/\(tenant)/api/WiadomoscSzczegoly",
            method: "PUT",
            body: body
        )
    }

    func mailboxes() async throws -> [Mailbox] {
        try await ensureInitialized()
        return try await fetchMailboxes()
    }

    func send(_ draft: MailDraft) async throws {
        let mailbox = try await resolveMailbox()
        let payload = PrometheusSendMessage(
            globalKey: UUID().uuidString,
            watekGlobalKey: UUID().uuidString,
            nadawcaSkrzynkaGlobalKey: mailbox.globalKey,
            adresaciSkrzynkiGlobalKeys: draft.recipients.map(\.globalKey),
            tytul: draft.subject,
            tresc: draft.body,
            zalaczniki: [],
            powitalna: false,
            odpowiedziana: nil,
            przekazana: nil
        )
        try await post(payload, endpoint: "/api/WiadomoscNowa")
    }

    func reply(_ draft: MailDraft, to id: String) async throws {
        let mailbox = try await resolveMailbox()
        let payload = PrometheusSendMessage(
            globalKey: UUID().uuidString,
            watekGlobalKey: UUID().uuidString,
            nadawcaSkrzynkaGlobalKey: mailbox.globalKey,
            adresaciSkrzynkiGlobalKeys: draft.recipients.map(\.globalKey),
            tytul: draft.subject,
            tresc: draft.body,
            zalaczniki: [],
            powitalna: false,
            odpowiedziana: id,
            przekazana: nil
        )
        try await post(payload, endpoint: "/api/WiadomoscOdpowiedzPrzekaz")
    }

    func forward(_ draft: MailDraft, from id: String) async throws {
        let mailbox = try await resolveMailbox()
        let payload = PrometheusSendMessage(
            globalKey: UUID().uuidString,
            watekGlobalKey: UUID().uuidString,
            nadawcaSkrzynkaGlobalKey: mailbox.globalKey,
            adresaciSkrzynkiGlobalKeys: draft.recipients.map(\.globalKey),
            tytul: draft.subject,
            tresc: draft.body,
            zalaczniki: [],
            powitalna: false,
            odpowiedziana: nil,
            przekazana: id
        )
        try await post(payload, endpoint: "/api/WiadomoscOdpowiedzPrzekaz")
    }

    // MARK: Initialization

    private func ensureInitialized() async throws {
        if isInitialized { return }
        guard !tenant.isEmpty, !login.isEmpty, !password.isEmpty else {
            throw PrometheusMailError.missingCredentials
        }

        if initialCookies.isEmpty {
            let storage = session.configuration.httpCookieStorage ?? .shared
            clearCookies(storage, hosts: [
                "dziennik-logowanie.vulcan.net.pl",
                "wiadomosci.eduvulcan.pl"
            ])
            do {
                let cookies = try await PrometheusLoginService(session: session)
                    .portalCookies(login: login, password: password)
                seedCookies(cookies, clearAll: false)
            } catch {
                throw PrometheusMailError.loginFailed
            }
        } else {
            seedCookies(initialCookies, clearAll: true)
        }

        try await authorize(firstAuthURL)
        try await authorize(secondAuthURL)

        let appPage = try await getHTML(appURL)
        let appHTML = appPage.html
        antiForgeryToken = Self.token("antiForgeryToken", in: appHTML) ?? ""
        appGuid = Self.token("appGuid", in: appHTML) ?? ""
        guard !antiForgeryToken.isEmpty, !appGuid.isEmpty else {
            throw PrometheusMailError.sessionExpired
        }

        isInitialized = true
    }

    private func authorize(_ url: URL) async throws {
        let (html, responseURL) = try await getHTML(url)
        guard let form = HTMLForm.first(in: html) else { return }
        let (secondHTML, secondURL) = try await submit(form, relativeTo: responseURL)
        if let second = HTMLForm.first(in: secondHTML) {
            _ = try await submit(second, relativeTo: secondURL)
        }
    }

    private func submit(_ form: HTMLForm, relativeTo base: URL) async throws -> (html: String, url: URL) {
        guard let url = form.url(relativeTo: base) else {
            throw PrometheusMailError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("pl-PL,pl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.httpBody = form.body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PrometheusMailError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PrometheusMailError.sessionExpired
        }
        if http.statusCode >= 400 {
            throw PrometheusMailError.server("Serwer logowania zwrócił błąd \(http.statusCode).")
        }
        return (String(decoding: data, as: UTF8.self), http.url ?? url)
    }

    private func getHTML(_ url: URL) async throws -> (html: String, url: URL) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("pl-PL,pl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PrometheusMailError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PrometheusMailError.sessionExpired
        }
        if http.statusCode >= 400 {
            throw PrometheusMailError.server("Serwer wiadomości zwrócił błąd \(http.statusCode).")
        }
        return (String(decoding: data, as: UTF8.self), http.url ?? url)
    }

    // MARK: Mailbox selection

    private func resolveMailbox() async throws -> Mailbox {
        try await ensureInitialized()
        if let selectedMailbox { return selectedMailbox }
        let boxes = try await fetchMailboxes()
        let matched = boxes.first { box in
            VulcanMailboxName.parse(box.name)?
                .matches(firstName: pupilFirstName, surname: pupilSurname) == true
        } ?? boxes.first { box in
            box.name.range(of: pupilFirstName, options: .caseInsensitive) != nil
                && box.name.range(of: pupilSurname, options: .caseInsensitive) != nil
        } ?? boxes.first
        guard let matched else {
            throw PrometheusMailError.noMailbox
        }
        selectedMailbox = matched
        return matched
    }

    private func fetchMailboxes() async throws -> [Mailbox] {
        let data = try await apiRequest(path: "/\(tenant)/api/Skrzynki")
        let boxes = try decoder.decode([PrometheusMailboxDTO].self, from: data)
        return boxes.map {
            Mailbox(globalKey: $0.globalKey, name: $0.nazwa, type: $0.typUzytkownika)
        }
    }

    // MARK: Request helpers

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    private func apiRequest(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        try await ensureInitialized()
        guard let baseURL = URL(string: path, relativeTo: messagesBase)?.absoluteURL else {
            throw PrometheusMailError.invalidResponse
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("pl-PL,pl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(appGuid, forHTTPHeaderField: "X-V-AppGuid")
        request.setValue(antiForgeryToken, forHTTPHeaderField: "X-V-RequestVerificationToken")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PrometheusMailError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PrometheusMailError.sessionExpired
        }
        if http.statusCode >= 400 {
            throw PrometheusMailError.server("Serwer wiadomości zwrócił błąd \(http.statusCode).")
        }
        return data
    }

    private func post(_ payload: PrometheusSendMessage, endpoint: String) async throws {
        let body = try JSONEncoder().encode(payload)
        _ = try await apiRequest(
            path: "/\(tenant)\(endpoint)",
            method: "POST",
            body: body
        )
    }

    // MARK: Cookies

    private func seedCookies(_ snapshots: [CookieSnapshot], clearAll: Bool) {
        let storage = session.configuration.httpCookieStorage ?? .shared
        if clearAll {
            clearCookies(storage, hosts: [
                "eduvulcan.pl",
                "dziennik-logowanie.vulcan.net.pl",
                "wiadomosci.eduvulcan.pl"
            ])
        } else {
            // A fresh portal login has already replaced the portal cookies.
            // Only clear stale SSO/mailbox cookies.
            clearCookies(storage, hosts: [
                "dziennik-logowanie.vulcan.net.pl",
                "wiadomosci.eduvulcan.pl"
            ])
        }

        let domains = [
            "eduvulcan.pl",
            "dziennik-logowanie.vulcan.net.pl",
            "wiadomosci.eduvulcan.pl"
        ]
        for snapshot in snapshots {
            for domain in domains {
                if let cookie = snapshot.cookie(for: domain) {
                    storage.setCookie(cookie)
                }
            }
        }
    }

    private func clearCookies(_ storage: HTTPCookieStorage, hosts: [String]) {
        for cookie in storage.cookies ?? [] {
            let domain = cookie.domain.lowercased()
            if hosts.contains(where: { domain.contains($0) || $0.contains(domain) }) {
                storage.deleteCookie(cookie)
            }
        }
    }

    // MARK: URLs

    private var firstAuthURL: URL {
        let prometheus = Self.encode("https://eduvulcan.pl")
        let sso = Self.encode("https://dziennik-logowanie.vulcan.net.pl")
        let student = Self.encode("https://uczen.eduvulcan.pl")
        let raw = "https://eduvulcan.pl/fs/ls?wa=wsignin1.0&wtrealm=\(sso)%2F\(tenant)%2FFs%2FLs%3Fwa%3Dwsignin1.0%26wtrealm%3D\(student)%2F\(tenant)%2FAccount%2FLogin%3FreturnUrl%3D\(prometheus)%26wctx%3Dauth%3DstudentEV%26nslo%3D1&wctx=nslo%3D1"
        return URL(string: raw) ?? portalBase
    }

    private var secondAuthURL: URL {
        let raw = "https://dziennik-logowanie.vulcan.net.pl/\(tenant)/Fs/Ls?wa=wsignin1.0&wtrealm=https://wiadomosci.eduvulcan.pl/\(tenant)/Account/Login?returnUrl=/\(tenant)/App&wctx=auth=studentEV&nslo=1"
        return URL(string: raw) ?? ssoBase
    }

    private var appURL: URL {
        URL(string: "https://wiadomosci.eduvulcan.pl/\(tenant)/App") ?? messagesBase
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func token(_ name: String, in html: String) -> String? {
        let pattern = "\(name)\\s*:\\s*['\"]([^'\"]+)['\"]"
        guard let groups = LoginPage.firstMatch(html, pattern), groups.count > 1 else {
            return nil
        }
        return groups[1].nilIfEmpty
    }

    private static func absoluteURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw) else { return nil }
        if url.scheme == nil {
            return URL(string: raw, relativeTo: URL(string: "https://wiadomosci.eduvulcan.pl")!)?.absoluteURL
        }
        return url
    }
}

// MARK: - HTML to text

enum MailText {
    static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"</p\s*>"#,
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
