import Foundation

/// One cookie in a private per-account jar.
///
/// Deliberately not `HTTPCookie`: the jar must preserve `Path=/OAuth` for
/// Librus's year-long `DeviceCookie` and must never fall back to the shared
/// process cookie storage.
struct LibrusCookie: Codable, Sendable, Hashable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresAt: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool

    func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    func matches(_ url: URL, now: Date = Date()) -> Bool {
        guard !isExpired(at: now) else { return false }
        if isSecure && url.scheme?.lowercased() != "https" { return false }
        let host = (url.host ?? "").lowercased()
        let domain = self.domain.lowercased()
        guard !host.isEmpty, !domain.isEmpty else { return false }
        guard host == domain || host.hasSuffix("." + domain) else { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        if path == "/" || requestPath == path { return true }
        guard requestPath.hasPrefix(path) else { return false }
        if path.hasSuffix("/") { return true }
        let boundary = requestPath.index(
            requestPath.startIndex,
            offsetBy: path.count,
            limitedBy: requestPath.endIndex
        )
        return boundary.map { $0 < requestPath.endIndex && requestPath[$0] == "/" } ?? false
    }

    // MARK: Parsing

    static func parse(_ header: String, for url: URL, now: Date = Date()) -> LibrusCookie? {
        let parts = header
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = parts.first,
              let separator = first.firstIndex(of: "=") else {
            return nil
        }
        let name = String(first[..<separator])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var value = String(first[first.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        var domain = host
        var path = defaultPath(for: url)
        var expiresAt: Date?
        var isSecure = false
        var isHTTPOnly = false

        for attribute in parts.dropFirst() {
            let pair = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawValue = pair.count > 1
                ? pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            switch key {
            case "domain":
                let normalized = rawValue
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    .lowercased()
                if !normalized.isEmpty {
                    domain = normalized
                }
            case "path":
                if rawValue.hasPrefix("/") {
                    path = rawValue
                }
            case "expires":
                if let date = httpDate(rawValue) {
                    expiresAt = date
                }
            case "max-age":
                if let seconds = Int(rawValue) {
                    expiresAt = now.addingTimeInterval(TimeInterval(seconds))
                }
            case "secure":
                isSecure = true
            case "httponly":
                isHTTPOnly = true
            default:
                break
            }
        }

        return LibrusCookie(
            name: name,
            value: value,
            domain: domain,
            path: path,
            expiresAt: expiresAt,
            isSecure: isSecure,
            isHTTPOnly: isHTTPOnly
        )
    }

    /// URLSession may hand back several cookies in one `Set-Cookie` header.
    /// A comma inside `Expires=Wed, 09 Jun…` must not split the header; a
    /// comma followed by `name=` must.
    static func splitCombined(_ header: String) -> [String] {
        var result: [String] = []
        var current = ""
        var index = header.startIndex
        while index < header.endIndex {
            let character = header[index]
            if character == "," {
                let rest = header[header.index(after: index)...]
                if isCookieStart(String(rest)) {
                    let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !piece.isEmpty { result.append(piece) }
                    current = ""
                } else {
                    current.append(character)
                }
            } else {
                current.append(character)
            }
            index = header.index(after: index)
        }
        let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty { result.append(piece) }
        return result
    }

    private static func isCookieStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(of: "=") else { return false }
        let name = trimmed[..<separator]
        guard !name.isEmpty else { return false }
        return !name.contains { $0.isWhitespace || $0 == ";" || $0 == "," }
    }

    private static func defaultPath(for url: URL) -> String {
        let requestPath = url.path.isEmpty ? "/" : url.path
        guard requestPath.hasPrefix("/") else { return "/" }
        guard let slash = requestPath.lastIndex(of: "/"), slash != requestPath.startIndex else {
            return "/"
        }
        return String(requestPath[..<slash])
    }

    private static func httpDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd-MMM-yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss zzz"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }
}

/// A private cookie jar. One actor instance belongs to exactly one Librus
/// account and is never shared.
actor LibrusCookieJar {
    /// Only these cookies survive a restart. `DeviceCookie` is the
    /// long-lived device-trust cookie and keeps normal logins captcha-free.
    static let persistedNames: [String: Set<String>] = [
        "synergia.librus.pl": ["oauth_token", "DZIENNIKSID", "SDZIENNIKSID"],
        "api.librus.pl": ["DeviceCookie", "DZIENNIKSID", "SDZIENNIKSID"],
        "wiadomosci.librus.pl": ["DZIENNIKSID", "SDZIENNIKSID"]
    ]

    private var cookies: [LibrusCookie] = []

    init(_ cookies: [LibrusCookie] = []) {
        self.cookies = cookies
    }

    func restore(_ cookies: [LibrusCookie]) {
        let now = Date()
        self.cookies = cookies.filter { !$0.isExpired(at: now) }
    }

    func store(_ setCookieHeaders: [String], for url: URL) {
        let now = Date()
        for header in setCookieHeaders {
            for piece in LibrusCookie.splitCombined(header) {
                guard let cookie = LibrusCookie.parse(piece, for: url, now: now) else {
                    continue
                }
                remove(cookie)
                if !cookie.isExpired(at: now) {
                    cookies.append(cookie)
                }
            }
        }
        removeExpired(at: now)
    }

    func header(for url: URL) -> String? {
        let now = Date()
        let matching = cookies
            .filter { $0.matches(url, now: now) }
            .sorted {
                if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
                return $0.name < $1.name
            }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func snapshot() -> [LibrusCookie] {
        let now = Date()
        return cookies.filter { !$0.isExpired(at: now) }
    }

    func snapshotPersistable() -> [LibrusCookie] {
        let now = Date()
        return cookies.filter { cookie in
            guard !cookie.isExpired(at: now),
                  let names = Self.persistedNames[cookie.domain.lowercased()] else {
                return false
            }
            return names.contains(cookie.name)
        }
    }

    func has(name: String, domain: String) -> Bool {
        let now = Date()
        return cookies.contains {
            $0.name == name
                && $0.domain.caseInsensitiveCompare(domain) == .orderedSame
                && !$0.isExpired(at: now)
        }
    }

    func clear() {
        cookies.removeAll()
    }

    private func remove(_ cookie: LibrusCookie) {
        cookies.removeAll {
            $0.name == cookie.name
                && $0.domain.caseInsensitiveCompare(cookie.domain) == .orderedSame
                && $0.path == cookie.path
        }
    }

    private func removeExpired(at now: Date) {
        cookies.removeAll { $0.isExpired(at: now) }
    }
}
