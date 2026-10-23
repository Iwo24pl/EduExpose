import Foundation

/// Minimal parser for the ASP.NET form posts used by the VULCAN SSO pages.
struct HTMLForm: Sendable {
    struct Field: Sendable {
        let name: String
        let value: String
    }

    let action: String
    let fields: [Field]

    static func first(in html: String) -> HTMLForm? {
        forms(in: html).first
    }

    /// The WS-Federation form (`wa` / `wresult` / `wctx`) that completes the
    /// eduVULCAN SSO handshake. SSO pages can contain other forms, so never
    /// submit whichever form happens to come first.
    static func sso(in html: String) -> HTMLForm? {
        forms(in: html).first { form in
            let names = Set(form.fields.map(\.name))
            return names.contains("wa")
                && names.contains("wresult")
                && names.contains("wctx")
        }
    }

    static func forms(in html: String) -> [HTMLForm] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<form\b[^>]*>.*?</form>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let text = html as NSString
        return regex.matches(
            in: html,
            range: NSRange(location: 0, length: text.length)
        ).map { match in
            let form = text.substring(with: match.range)
            return parse(form, action: LoginPage.attribute(form, "action") ?? "")
        }
    }

    private static func parse(_ form: String, action: String) -> HTMLForm {
        var fields: [Field] = []
        if let regex = try? NSRegularExpression(
            pattern: #"<input\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let nsForm = form as NSString
            for match in regex.matches(
                in: form,
                range: NSRange(location: 0, length: nsForm.length)
            ) {
                let tag = nsForm.substring(with: match.range)
                guard LoginPage.attribute(tag, "type")?.lowercased() == "hidden",
                      let name = LoginPage.attribute(tag, "name"),
                      !name.isEmpty else {
                    continue
                }
                fields.append(Field(
                    name: name,
                    value: HTMLEntities.decode(LoginPage.attribute(tag, "value") ?? "")
                ))
            }
        }

        return HTMLForm(action: HTMLEntities.decode(action), fields: fields)
    }

    func url(relativeTo base: URL) -> URL? {
        let target = action.trimmingCharacters(in: .whitespacesAndNewlines)
        // A form with no action posts back to the page that rendered it.
        guard !target.isEmpty else { return base }
        return URL(string: target, relativeTo: base)?.absoluteURL
    }

    var body: Data {
        Data(FormURLEncoding.encode(fields.map { ($0.name, $0.value) }).utf8)
    }
}

/// `application/x-www-form-urlencoded` encoding.
///
/// `URLComponents` is not a form encoder: it leaves `+` untouched, but form
/// servers decode a literal `+` as a space. SAML `wresult` tokens are base64
/// and commonly contain `+`, so using `URLComponents` corrupts the SSO token.
enum FormURLEncoding {
    static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")
    }

    private static func escape(_ value: String) -> String {
        // ASCII unreserved set only; non-ASCII is sent as percent-encoded UTF-8.
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._* "
        )
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return ""
        }
        return encoded.replacingOccurrences(of: " ", with: "+")
    }
}

/// Decodes the entities that appear in the VULCAN forms and message bodies.
enum HTMLEntities {
    static func decode(_ value: String) -> String {
        decodeNumericEntities(value)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Handles both `&#39;` and `&#x27;`, including characters outside the BMP.
    private static func decodeNumericEntities(_ value: String) -> String {
        guard value.contains("&#"),
              let regex = try? NSRegularExpression(
                pattern: #"&#(x?)([0-9A-Fa-f]+);"#,
                options: [.caseInsensitive]
              ) else {
            return value
        }

        let text = value as NSString
        let matches = regex.matches(
            in: value,
            range: NSRange(location: 0, length: text.length)
        )
        guard !matches.isEmpty else { return value }

        var result = ""
        var cursor = 0
        for match in matches {
            result += text.substring(
                with: NSRange(location: cursor, length: match.range.location - cursor)
            )
            let isHex = text.substring(with: match.range(at: 1)).isEmpty == false
            let digits = text.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10),
               let scalar = Unicode.Scalar(code) {
                result.append(contentsOf: String(scalar))
            } else {
                result += text.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += text.substring(from: cursor)
        return result
    }
}
