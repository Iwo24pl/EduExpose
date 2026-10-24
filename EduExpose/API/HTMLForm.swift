import Foundation

/// Minimal parser for the ASP.NET form posts used by the VULCAN SSO pages.
struct HTMLForm: Sendable {
    struct Field: Sendable {
        let name: String
        let value: String
    }

    let action: String
    let name: String
    let fields: [Field]

    static func first(in html: String) -> HTMLForm? {
        forms(in: html).first
    }

    /// The WS-Federation form that completes the eduVULCAN SSO handshake.
    /// Proven clients (JS `hebece-prometheusweb`) select `form[name=hiddenform]`;
    /// fall back to field matching when the name is absent.
    static func sso(in html: String) -> HTMLForm? {
        hiddenform(in: html) ?? forms(in: html).first { form in
            let names = Set(form.fields.map(\.name))
            return names.contains("wa")
                && names.contains("wresult")
                && names.contains("wctx")
        }
    }

    /// Selects `<form name="hiddenform">` like the working JS implementation.
    static func hiddenform(in html: String) -> HTMLForm? {
        forms(in: html).first { $0.name.lowercased() == "hiddenform" }
    }

    static func forms(in html: String) -> [HTMLForm] {
        var forms: [HTMLForm] = []
        var searchStart = html.startIndex
        while let start = html.range(
            of: "<form",
            options: [.caseInsensitive],
            range: searchStart..<html.endIndex
        )?.lowerBound {
            let after = html.index(after: start)
            guard after < html.endIndex, html[after].isWhitespace || html[after] == ">" else {
                searchStart = html.index(after: start)
                continue
            }
            guard let tagEnd = tagEnd(in: html, from: start),
                  let closeRange = html.range(
                    of: "</form>",
                    options: [.caseInsensitive],
                    range: tagEnd..<html.endIndex
                  ) else {
                break
            }
            forms.append(parse(
                opening: String(html[start..<tagEnd]),
                body: String(html[tagEnd..<closeRange.lowerBound])
            ))
            searchStart = closeRange.upperBound
        }
        return forms
    }

    private static func parse(opening: String, body: String) -> HTMLForm {
        var fields: [Field] = []
        var searchStart = body.startIndex
        while let start = body.range(
            of: "<input",
            options: [.caseInsensitive],
            range: searchStart..<body.endIndex
        )?.lowerBound {
            let after = body.index(after: start)
            guard after < body.endIndex, body[after].isWhitespace || body[after] == ">" else {
                searchStart = body.index(after: start)
                continue
            }
            guard let tagEnd = tagEnd(in: body, from: start) else { break }
            let tag = String(body[start..<tagEnd])
            searchStart = tagEnd
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

        return HTMLForm(
            action: HTMLEntities.decode(LoginPage.attribute(opening, "action") ?? ""),
            name: LoginPage.attribute(opening, "name") ?? "",
            fields: fields
        )
    }

    /// HTML5-ish tag end: `>` inside a quoted attribute value does not close the
    /// tag. VULCAN's SAML `wresult` value contains raw `>` characters, so the
    /// old `<input\b[^>]*>` pattern truncated the token, `value` had no closing
    /// quote left, and the POST carried an empty assertion.
    static func tagEnd(in text: String, from tagStart: String.Index) -> String.Index? {
        var quote: Character?
        var index = text.index(after: tagStart)
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return text.index(after: index)
            }
            index = text.index(after: index)
        }
        return nil
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

    /// Token-safe shape of the values: lengths only, plus a flag when a value
    /// already looks percent-encoded (re-encoding it would corrupt the token).
    var fieldShape: String {
        let parts = fields.map { field -> String in
            let value = field.value
            let encoded = value.contains("%3D") || value.contains("%2F") || value.contains("%2B")
            return "\(field.name)=\(value.count)\(encoded ? "!pct" : "")"
        }
        return " [" + parts.joined(separator: ",") + "]"
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
