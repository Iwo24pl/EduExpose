import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Linux-only typecheck stubs. These are never part of the app target.
// They model only the signatures the backend touches.

enum LoginPage {
    static func attribute(_ tag: String, _ name: String) -> String? { nil }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {}

actor HebeClient {
    init(credential: HebeCredential, session: URLSession) {}
    init(student: StoredStudent, session: URLSession) {}

    func grades(unitId: Int, pupilId: Int, periodId: Int) async throws -> [Grade] { [] }
    func averages(unitId: Int, pupilId: Int, periodId: Int) async throws -> [GradeAverage] { [] }
    func schedule(pupilId: Int, from: String, to: String) async throws -> [Schedule] { [] }
    func exams(pupilId: Int, from: String, to: String) async throws -> [Exam] { [] }
    func homework(pupilId: Int, from: String, to: String) async throws -> [Homework] { [] }
    func notes(pupilId: Int) async throws -> [Note] { [] }
    func announcements(unitId: Int, pupilId: Int) async throws -> [Announcement] { [] }
    func luckyNumber(pupilId: Int, constituentId: Int, day: String) async throws -> LuckyNumber? { nil }
}

struct PrometheusLoginService {
    let session: URLSession

    func signIn(login: String, password: String) async throws -> [StoredStudent] { [] }
}

struct Logger {
    init(subsystem: String, category: String) {}
    func debug(_ message: String) {}
}

enum MailText {
    static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?is)<style\b[^>]*>.*?</style\s*>"#,
            with: "",
            options: .regularExpression
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
            of: #"<[^>]+>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
