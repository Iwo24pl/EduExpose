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
        guard let form = LoginPage.firstMatch(
            html,
            #"<form\b[^>]*>.*?</form>"#
        )?.first,
            let action = LoginPage.attribute(form, "action"),
            !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

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
        URL(string: action, relativeTo: base)?.absoluteURL
    }

    var body: Data {
        var components = URLComponents()
        components.queryItems = fields.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        return Data((components.percentEncodedQuery ?? "").utf8)
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
