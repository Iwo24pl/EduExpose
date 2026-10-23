import Foundation
import os

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
    private var initialization: Task<Void, Error>?
    private var selectedMailbox: Mailbox?
    private var antiForgeryToken = ""
    private var appGuid = ""
    private var apiBase: URL?
    private var postLoginURL: URL?

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
            endpoint = "OdebraneSkrzynka"
        case .sent:
            endpoint = "WyslaneSkrzynka"
        case .deleted:
            endpoint = "UsunieteSkrzynka"
        }

        let data = try await apiRequest(
            endpoint: endpoint,
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
            endpoint: "WiadomoscSzczegoly",
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
            endpoint: "WiadomoscSzczegoly",
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
        try await post(payload, endpoint: "WiadomoscNowa")
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
        try await post(payload, endpoint: "WiadomoscOdpowiedzPrzekaz")
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
        try await post(payload, endpoint: "WiadomoscOdpowiedzPrzekaz")
    }

    // MARK: Initialization

    private func ensureInitialized() async throws {
        if isInitialized { return }
        // The UI loads messages and mailboxes together. Two callers entering
        // this actor before the first `await` would each start a portal login on
        // the same shared cookie jar and cancel one another (NSURLError -999).
        if let initialization {
            try await initialization.value
            return
        }
        let task = Task { try await performInitialization() }
        initialization = task
        do {
            try await task.value
            isInitialized = true
            initialization = nil
        } catch {
            initialization = nil
            throw error
        }
    }

    private func performInitialization() async throws {
        guard !tenant.isEmpty else {
            throw PrometheusMailError.missingCredentials
        }

        let usedStoredCookies = !initialCookies.isEmpty
        await trace("init", "tenant=\(tenant) storedCookies=\(usedStoredCookies)")
        if usedStoredCookies {
            seedCookies(initialCookies, clearAll: true)
            await trace(
                "cookies.stored",
                initialCookies.map { "\($0.name)@\($0.domain)" }.joined(separator: ",")
            )
        } else {
            guard !login.isEmpty, !password.isEmpty else {
                throw PrometheusMailError.missingCredentials
            }
            try await signInForCookies()
        }

        do {
            try await completeSSO()
        } catch {
            guard usedStoredCookies,
                  let mailError = error as? PrometheusMailError,
                  case .sessionExpired = mailError,
                  !login.isEmpty,
                  !password.isEmpty else {
                throw error
            }
            // Cookies captured after logging in can expire while the app is
            // open; authenticate once more before giving up.
            await trace("init.retry", "session expired with stored cookies")
            try await signInForCookies()
            try await completeSSO()
        }
    }

    private func signInForCookies() async throws {
        await trace("login.start", "clearing portal and SSO cookies")
        // Start from a clean jar so the portal chain belongs to this account,
        // not to whatever account last used the shared cookie storage.
        let storage = session.configuration.httpCookieStorage ?? .shared
        clearCookies(storage, hosts: [
            "eduvulcan.pl",
            "uczen.eduvulcan.pl",
            "dziennik-logowanie.vulcan.net.pl",
            "wiadomosci.eduvulcan.pl"
        ])

        // Follow the mailbox -> STS -> portal chain with redirects disabled to
        // discover the exact login URL (including its ReturnUrl). Reconstructing
        // that URL by hand gets the double encoding wrong.
        let loginURL: URL?
        switch await discoverLoginURL() {
        case .needed(let url):
            loginURL = url
            await trace("login.discovery", "login \(MailTraceRedaction.safeURL(url))")
        case .alreadySignedIn:
            await trace("login.discovery", "already signed in")
            return
        case .failed:
            await trace("login.discovery", "failed; using plain login page")
            loginURL = nil
        }

        let portal: PortalSession
        do {
            portal = try await PrometheusLoginService(session: session)
                .portalCookies(
                    login: login,
                    password: password,
                    loginURL: loginURL
                )
        } catch {
            await trace("login.error", "\(String(describing: error))")
            throw PrometheusMailError.loginFailed
        }
        guard !portal.cookies.isEmpty else {
            await trace("login.error", "no portal cookies")
            throw PrometheusMailError.loginFailed
        }
        await trace(
            "login.ok",
            "cookies=\(portal.cookies.count) names=\(portal.cookies.map { "\($0.name)@\($0.domain)" }.joined(separator: ",")) postLogin=\(portal.postLoginURL.map(MailTraceRedaction.safeURL) ?? "-")"
        )
        postLoginURL = portal.postLoginURL
        seedCookies(portal.cookies, clearAll: false)
    }

    private enum LoginDiscovery {
        case needed(URL)
        case alreadySignedIn
        case failed
    }

    /// Records one redacted step for the settings diagnostics.
    private func trace(_ stage: String, _ detail: String) async {
        await MailTraceStore.shared.record(stage, detail)
    }

    private func discoverLoginURL() async -> LoginDiscovery {
        var request = URLRequest(url: appURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("pl-PL,pl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        // Let URLSession follow the chain so cookies are processed exactly as
        // in a browser. Its final URL is the login page carrying ReturnUrl.
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              let finalURL = http.url else {
            return .failed
        }

        let host = finalURL.host?.lowercased() ?? ""
        let path = finalURL.path.lowercased()
        await trace(
            "discovery.final",
            "\(http.statusCode) \(MailTraceRedaction.safeURL(finalURL))"
        )

        if path.contains("logowanie") {
            return .needed(finalURL)
        }
        if host.contains("wiadomosci") && !path.contains("login") {
            return .alreadySignedIn
        }
        return .failed
    }

    /// Follows the WS-Federation handshake instead of assuming a fixed number
    /// of intermediate forms. Starting at the mailbox itself mirrors a browser:
    /// its redirect chain goes through the portal and ends at the app page.
    private func completeSSO() async throws {
        // Diary first: the proven path to the real mailbox URL.
        if let diaryURL = await diaryWiadomosciURL() {
            do {
                let page = try await followSSO(from: diaryURL)
                if let metadata = mailboxMetadata(from: page) {
                    apply(metadata)
                    await trace(
                        "metadata.ok",
                        "via-diary api=\(metadata.apiURL.map(MailTraceRedaction.safeURL) ?? "-")"
                    )
                    return
                }
            } catch let error as PrometheusMailError {
                await trace("sso.diary.entry.error", "\(String(describing: error))")
            }
        }
        // The mailbox redirects through the portal by itself. The explicit SSO
        // entry points remain as a fallback for older accounts.
        var entries = [appURL]
        if let postLoginURL {
            entries.append(postLoginURL)
        }
        entries.append(secondAuthURL)
        entries.append(appURL)

        var lastError = PrometheusMailError.sessionExpired
        var seen = Set<String>()
        for url in entries {
            guard seen.insert(url.absoluteString).inserted else { continue }
            await trace("sso.entry", MailTraceRedaction.safeURL(url))
            do {
                let page = try await followSSO(from: url)
                if let metadata = mailboxMetadata(from: page) {
                    apply(metadata)
                    await trace(
                        "metadata.ok",
                        "api=\(metadata.apiURL.map(MailTraceRedaction.safeURL) ?? "-")"
                    )
                    return
                }
            } catch let error as PrometheusMailError {
                // A rejected entry point should not prevent trying the next one.
                lastError = error
                await trace("sso.entry.error", "\(String(describing: error))")
            }
        }
        await trace("sso.failed", "\(String(describing: lastError))")
        throw lastError
    }

    /// Diary-first handshake (proven by the JS `hebece-prometheusweb` client):
    /// the diary (`Uczeń`) SSO session issues the real `wiadomosciUrl` in its
    /// `VParam`. The journal tiles live on the signed-in portal home; the
    /// `dostep-do-dziennik` marketing page only links there.
    private func diaryWiadomosciURL() async -> URL? {
        let sources = [
            URL(string: "https://eduvulcan.pl/"),
            URL(string: "https://eduvulcan.pl/dostep-do-dziennik/")
        ].compactMap { $0 }

        for source in sources {
            do {
                let page = try await getHTML(source)
                await trace("sso.diary.access", MailTraceRedaction.safeURL(page.url))
                guard let journal = Self.diaryLink(in: page.html, relativeTo: page.url) else {
                    await trace("sso.diary.nolink", MailTraceRedaction.safeURL(page.url))
                    continue
                }
                await trace("sso.diary.journal", MailTraceRedaction.safeURL(journal))
                var current = try await getHTML(journal)
                var visited = Set<String>()
                for _ in 0..<2 {
                    let signature = "\(current.url.absoluteString)|\(current.html.count)"
                    guard visited.insert(signature).inserted else { break }
                    guard let form = HTMLForm.hiddenform(in: current.html) ?? HTMLForm.sso(in: current.html) else {
                        break
                    }
                    current = try await submit(form, relativeTo: current.url)
                }
                let metadata = MailSessionMetadata.parse(current.html)
                if let url = metadata.wiadomosciURL {
                    await trace("sso.diary.wiadomosci", MailTraceRedaction.safeURL(url))
                    return url
                }
                await trace("sso.diary.novparam", "\(MailTraceRedaction.safeURL(current.url)) head=\(MailTraceRedaction.htmlHead(current.html))")
            } catch {
                await trace("sso.diary.error", "\(String(describing: error))")
            }
        }
        return nil
    }

    /// Only diary hosts count. A link containing the word `dziennik` is usually
    /// this very page, and following it used to loop back to the marketing site.
    private static func diaryLink(in html: String, relativeTo base: URL) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b[^>]*\bhref\s*=\s*"([^"]+)"[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let text = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let href = HTMLEntities.decode(text.substring(with: match.range(at: 1)))
            guard let resolved = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            let host = resolved.host?.lowercased() ?? ""
            if host.hasPrefix("uczen.") {
                return resolved
            }
        }
        return nil
    }

    private func followSSO(from url: URL) async throws -> (html: String, url: URL) {
        var page = try await getHTML(url)
        var visited = Set<String>()
        for _ in 0..<10 {
            let signature = "\(page.url.absoluteString)|\(page.html.count)"
            guard visited.insert(signature).inserted else {
                // The same page keeps coming back: the remote side is rejecting
                // our token and re-issuing a fresh one. Repeating it ten times
                // only burns requests and hides the cause.
                await trace(
                    "sso.loop",
                    "\(MailTraceRedaction.safeURL(page.url)) bytes=\(page.html.count) cookies=\(cookieNames(hostSuffix: "vulcan.net.pl").joined(separator: ","))"
                )
                return page
            }
            let metadata = MailSessionMetadata.parse(page.html)
            let form = HTMLForm.sso(in: page.html)
            let forms = HTMLForm.forms(in: page.html).count
            await trace(
                "sso.page",
                "\(MailTraceRedaction.safeURL(page.url)) forms=\(forms) ssoForm=\(form != nil) name=\(form?.name ?? "-") action=\(form.map { MailTraceRedaction.safeURL($0.url(relativeTo: page.url) ?? page.url) } ?? "-") tokens=\(metadata.isComplete) bytes=\(page.html.count)"
            )
            if mailboxMetadata(from: page) != nil {
                return page
            }
            guard let form else {
                await trace("sso.stop", "head=\(MailTraceRedaction.htmlHead(page.html))")
                return page
            }
            page = try await submit(form, relativeTo: page.url)
        }
        return page
    }

    /// Cookie names currently held for hosts ending in `hostSuffix`. Values are
    /// never logged; only presence tells us whether URLSession dropped a cookie.
    private func cookieNames(hostSuffix: String) -> [String] {
        let storage = session.configuration.httpCookieStorage ?? .shared
        let name = hostSuffix.lowercased()
        return (storage.cookies ?? [])
            .filter { $0.domain.lowercased().contains(name) }
            .map(\.name)
            .sorted()
    }

    /// The student app also embeds `antiForgeryToken`/`appGuid`; those must not
    /// be mistaken for the mailbox session, so require a mailbox host or apiUrl.
    private func mailboxMetadata(from page: (html: String, url: URL)) -> MailSessionMetadata? {
        let metadata = MailSessionMetadata.parse(page.html)
        guard metadata.isComplete else { return nil }
        let pageHost = page.url.host?.lowercased() ?? ""
        let apiHost = metadata.apiURL?.host?.lowercased() ?? ""
        guard pageHost.contains("wiadomosci") || apiHost.contains("wiadomosci") else {
            return nil
        }
        return metadata
    }

    private func apply(_ metadata: MailSessionMetadata) {
        antiForgeryToken = metadata.antiForgeryToken
        appGuid = metadata.appGuid
        if let apiURL = metadata.apiURL,
           apiURL.host?.lowercased().contains("wiadomosci") == true {
            apiBase = apiURL
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
        // A form that posts back to the page it came from cannot advance an SSO
        // handshake; browsers submit WS-Fed forms to the realm host.
        let selfPost = url.absoluteString == base.absoluteString
        await trace(
            "http.post.req",
            "\(MailTraceRedaction.safeURL(url)) from=\(MailTraceRedaction.safeURL(base)) selfPost=\(selfPost) fields=\(form.fields.map(\.name).joined(separator: ","))\(form.fieldShape)"
        )
        request.httpBody = form.body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PrometheusMailError.invalidResponse
        }
        await trace(
            "http.post",
            "\(http.statusCode) -> \(MailTraceRedaction.safeURL(http.url ?? url)) bytes=\(data.count) cookieHosts=\(cookieNames(hostSuffix: url.host ?? "").joined(separator: ","))"
        )
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
        await trace(
            "http.get",
            "\(http.statusCode) \(MailTraceRedaction.safeURL(http.url ?? url)) bytes=\(data.count) cookies=\(cookieNames(hostSuffix: http.url?.host ?? url.host ?? "").joined(separator: ","))"
        )
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
            VulcanMailboxName.containsWord(pupilFirstName, in: box.name)
                && VulcanMailboxName.containsWord(pupilSurname, in: box.name)
        } ?? boxes.first
        guard let matched else {
            throw PrometheusMailError.noMailbox
        }
        selectedMailbox = matched
        return matched
    }

    private func fetchMailboxes() async throws -> [Mailbox] {
        let data = try await apiRequest(endpoint: "Skrzynki")
        let boxes = try decoder.decode([PrometheusMailboxDTO].self, from: data)
        return boxes.map {
            Mailbox(globalKey: $0.globalKey, name: $0.nazwa, type: $0.typUzytkownika)
        }
    }

    // MARK: Request helpers

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    /// `apiUrl` from the signed-in page can point at a different host or path;
    /// fall back to the historical tenant endpoint when it is absent.
    private var resolvedAPIBase: URL {
        if let apiBase { return apiBase }
        return messagesBase
            .appendingPathComponent(tenant)
            .appendingPathComponent("api")
    }

    private func apiEndpoint(_ endpoint: String) -> URL {
        resolvedAPIBase.appendingPathComponent(endpoint)
    }

    private func apiRequest(
        endpoint: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        try await ensureInitialized()
        let baseURL = apiEndpoint(endpoint)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
            // URLComponents leaves `+` unescaped; API form decoding treats it
            // as a space, so escape it explicitly.
            if let encoded = components?.percentEncodedQuery {
                components?.percentEncodedQuery = encoded
                    .replacingOccurrences(of: "+", with: "%2B")
            }
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
        await trace(
            "api",
            "\(method) \(endpoint) \(http.statusCode) bytes=\(data.count)"
        )
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
            endpoint: endpoint,
            method: "POST",
            body: body
        )
    }

    // MARK: Cookies

    private func seedCookies(_ snapshots: [CookieSnapshot], clearAll: Bool) {
        let storage = session.configuration.httpCookieStorage ?? .shared
        if clearAll {
            // A fresh portal login clears its own host before logging in, and
            // its post-login redirect sets the SSO/mailbox cookies. Do not clear
            // those here or the handshake is thrown away.
            clearCookies(storage, hosts: [
                "eduvulcan.pl",
                "uczen.eduvulcan.pl",
                "dziennik-logowanie.vulcan.net.pl",
                "wiadomosci.eduvulcan.pl"
            ])
        }

        for snapshot in snapshots {
            if let cookie = snapshot.cookie {
                storage.setCookie(cookie)
            }
        }
    }

    private func clearCookies(_ storage: HTTPCookieStorage, hosts: [String]) {
        for cookie in storage.cookies ?? [] {
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if hosts.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) {
                storage.deleteCookie(cookie)
            }
        }
    }

    // MARK: URLs

    /// Direct STS fallback for accounts whose portal chain is unavailable.
    private var secondAuthURL: URL {
        let raw = "https://dziennik-logowanie.vulcan.net.pl/\(tenant)/Fs/Ls?wa=wsignin1.0&wtrealm=https://wiadomosci.eduvulcan.pl/\(tenant)/Account/Login?returnUrl=/\(tenant)/App&wctx=auth=studentEV&nslo=1"
        return URL(string: raw) ?? ssoBase
    }

    private var appURL: URL {
        URL(string: "https://wiadomosci.eduvulcan.pl/\(tenant)/App") ?? messagesBase
    }

    private static func absoluteURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let resolved = url.scheme == nil
            ? URL(string: trimmed, relativeTo: URL(string: "https://wiadomosci.eduvulcan.pl")!)?.absoluteURL
            : url
        // Attachments are opened outside the app, so only web links are safe.
        guard let resolved,
              let scheme = resolved.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return resolved
    }
}

// MARK: - Session metadata

/// Values embedded in the signed-in mailbox page (usually inside `VParam`).
struct MailSessionMetadata: Equatable, Sendable {
    let antiForgeryToken: String
    let appGuid: String
    let apiURL: URL?
    /// Diary (`Uczeń`) pages expose the mailbox entry point here; the working
    /// JS client reads `wiadomosciUrl` instead of constructing the host.
    let wiadomosciURL: URL?

    var isComplete: Bool {
        !antiForgeryToken.isEmpty && !appGuid.isEmpty
    }

    static func parse(_ html: String) -> MailSessionMetadata {
        if let vparam = parseVParamJSON(html) {
            return vparam
        }
        return MailSessionMetadata(
            antiForgeryToken: value("antiForgeryToken", in: html) ?? "",
            appGuid: value("appGuid", in: html) ?? "",
            apiURL: webURL(value("apiUrl", in: html)),
            wiadomosciURL: webURL(value("wiadomosciUrl", in: html))
        )
    }

    /// The proven clients parse `var VParam = {...};` as JSON. Prefer that over
    /// per-token regexes; it also yields `wiadomosciUrl` and `apiUrl` exactly.
    private static func parseVParamJSON(_ html: String) -> MailSessionMetadata? {
        let pattern = #"var\s+VParam\s*=\s*(\{.*?\});"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let text = html as NSString
        guard let match = regex.firstMatch(
            in: html,
            range: NSRange(location: 0, length: text.length)
        ), match.numberOfRanges > 1 else {
            return nil
        }
        var raw = text.substring(with: match.range(at: 1))
        // JS sources tolerate trailing commas / single quotes; normalize best-effort.
        raw = raw.replacingOccurrences(of: "'", with: "\"")
        raw = raw.replacingOccurrences(
            of: #",(\s*[}\]])"#,
            with: "$1",
            options: .regularExpression
        )
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        func string(_ keys: String...) -> String {
            for key in keys {
                if let value = json[key] as? String, !value.isEmpty {
                    return HTMLEntities.decode(value)
                }
                // Case-insensitive fallback.
                if let found = json.first(where: { $0.key.lowercased() == key.lowercased() })?.value as? String,
                   !found.isEmpty {
                    return HTMLEntities.decode(found)
                }
            }
            return ""
        }
        let token = string("antiForgeryToken")
        let guid = string("appGuid")
        guard !token.isEmpty || !guid.isEmpty else { return nil }
        return MailSessionMetadata(
            antiForgeryToken: token,
            appGuid: guid,
            apiURL: webURL(string("apiUrl")),
            wiadomosciURL: webURL(string("wiadomosciUrl"))
        )
    }

    /// The live page uses `antiForgeryToken: '...'`; other builds use `=`.
    /// Accept both, with or without quotes around the key, and skip empty
    /// placeholders that a template may render before the real value.
    private static func value(_ name: String, in html: String) -> String? {
        let pattern = #"["']?\b\#(name)\b["']?\s*[:=]\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let text = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: text.length)
        )
        for match in matches {
            let raw = text.substring(with: match.range(at: 1))
            let decoded = HTMLEntities.decode(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty {
                return decoded
            }
        }
        return nil
    }

    private static func webURL(_ raw: String?) -> URL? {
        guard let raw,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}

// MARK: - HTML to text

enum MailText {
    static func plainText(from html: String) -> String {
        var text = html
        // Script and style contents are code, not message text.
        text = text.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            with: "",
            options: [.regularExpression]
        )
        text = text.replacingOccurrences(
            of: #"(?is)<style\b[^>]*>.*?</style\s*>"#,
            with: "",
            options: [.regularExpression]
        )
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
            of: #"</(?:div|li|tr|h[1-6])\s*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = HTMLEntities.decode(text)
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: [.regularExpression]
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
