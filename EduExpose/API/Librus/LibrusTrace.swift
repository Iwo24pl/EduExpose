import Foundation
import os

/// One redacted diagnostics event. Endpoints are stored without query
/// values; responses, cookies, headers and credentials never enter the
/// trace.
struct LibrusTraceEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let stage: String
    let endpoint: String?
    let status: Int?
    let note: String?

    var dumpLine: String {
        let time = date.formatted(date: .omitted, time: .standard)
        let endpoint = endpoint ?? "-"
        let status = status.map(String.init) ?? "-"
        let note = note.map { " (\($0))" } ?? ""
        return "\(time) [\(stage)] \(endpoint) \(status)\(note)"
    }
}

actor LibrusTrace {
    static let shared = LibrusTrace()

    private var events: [LibrusTraceEvent] = []
    private let limit = 240
    private let logger = Logger(subsystem: "com.iwo24pl.eduexpose", category: "librus")

    func record(
        _ stage: String,
        endpoint: String? = nil,
        status: Int? = nil,
        note: String? = nil
    ) {
        events.append(LibrusTraceEvent(
            date: Date(),
            stage: stage,
            endpoint: endpoint,
            status: status,
            note: note
        ))
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
        // Stage, endpoint and status are deliberately non-sensitive; the
        // note is an enumerated code, never server text.
        logger.debug("\(stage) \(endpoint ?? "-") \(status ?? 0)")
    }

    func snapshot() -> [LibrusTraceEvent] {
        events
    }

    func clear() {
        events.removeAll()
    }

    /// Host and path only. Query values can carry identifiers or tokens.
    nonisolated static func endpoint(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? "-"
        let path = url.path.isEmpty ? "/" : url.path
        return host + path
    }
}
