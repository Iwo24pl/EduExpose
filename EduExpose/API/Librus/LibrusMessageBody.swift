import Foundation

/// Decodes the base64/XML/HTML body Librus returns for a message.
enum LibrusMessageBody {
    static func decode(_ base64: String?) -> String {
        guard let base64, !base64.isEmpty else { return "" }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return MailText.plainText(from: base64)
        }

        var text = String(decoding: data, as: UTF8.self)
        if let start = text.range(of: "<![CDATA["),
           let end = text.range(of: "]]>", range: start.upperBound..<text.endIndex) {
            text = String(text[start.upperBound..<end.lowerBound])
        }
        return MailText.plainText(from: text)
    }
}
