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
                    value: decodeEntities(LoginPage.attribute(tag, "value") ?? "")
                ))
            }
        }

        return HTMLForm(action: decodeEntities(action), fields: fields)
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

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
