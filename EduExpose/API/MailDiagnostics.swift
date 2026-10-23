import Foundation
import os

/// One step of a mailbox session attempt. Values that can contain session
/// tokens are never stored here; only URLs (without query values), cookie
/// names, form names and statuses.
struct MailTraceEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let stage: String
    let detail: String

    var dumpLine: String {
        "\(date.formatted(date: .omitted, time: .standard)) [\(stage)] \(detail)"
    }
}

/// In-memory trace shared by the mailbox client and the settings screen.
actor MailTraceStore {
    static let shared = MailTraceStore()

    private var events: [MailTraceEvent] = []
    private let limit = 200
    private let logger = Logger(subsystem: "com.iwo24pl.eduexpose", category: "mail")

    func record(_ stage: String, _ detail: String) {
        events.append(MailTraceEvent(date: Date(), stage: stage, detail: detail))
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
        logger.debug("\(stage, privacy: .public): \(detail, privacy: .public)")
    }

    func snapshot() -> [MailTraceEvent] {
        events
    }

    func clear() {
        events.removeAll()
    }
}

enum MailTraceRedaction {
    /// Shows host/path and query key names but strips all query values, which
    /// can contain SAML tokens.
    static func safeURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "-"
        }
        let names = components.queryItems?.map(\.name) ?? []
        components.query = nil
        components.fragment = nil
        let base = components.string ?? "-"
        return names.isEmpty ? base : "\(base)?[\(names.joined(separator: ","))]"
    }

    /// A short failure snippet with token values removed.
    static func htmlHead(_ html: String, limit: Int = 2048) -> String {
        var text = String(html.prefix(limit))
        // Tokens and SAML payloads are long quoted strings; drop them first.
        text = text.replacingOccurrences(
            of: #"['"][^'"]{200,}['"]"#,
            with: "\"<redacted>\"",
            options: [.regularExpression]
        )
        for key in [
            "antiForgeryToken",
            "appGuid",
            "wresult",
            "wctx",
            "__RequestVerificationToken",
            "Set-Cookie"
        ] {
            let pattern = "(\(key)\\s*[:=]\\s*['\"]?)([^'\"\\s<]+)"
            text = text.replacingOccurrences(
                of: pattern,
                with: "$1<redacted>",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return text
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
