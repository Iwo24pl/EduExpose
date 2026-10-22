import Foundation
import Testing

@testable import EduExpose

struct SigningTests {
    @Test("Canonical URL matches the Kotlin signer")
    func canonicalURL() {
        let url = "https://lekcjaplus.vulcan.net.pl/krakow/api/mobile/grade/byPupil"
        #expect(Signing.canonicalURL(url) == "api%2fmobile%2fgrade%2fbypupil")
    }

    @Test("Signature date is RFC 1123 in GMT+0000")
    func signatureDate() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(Signing.signatureDate(date) == "Thu, 01 Jan 1970 00:00:00 GMT+0000")
    }
}

struct VulcanDateTests {
    @Test("Parses a day without a time zone shift")
    func parsesDay() throws {
        let date = try #require(VulcanDate.day("2024-02-29"))
        #expect(VulcanDate.dateString(date) == "2024-02-29")
    }

    @Test("Week starts on Monday")
    func weekStart() throws {
        let thursday = try #require(VulcanDate.day("2026-10-22"))
        #expect(VulcanDate.dateString(VulcanDate.startOfWeek(thursday)) == "2026-10-19")
    }

    @Test("Adds days across a month boundary")
    func addsDays() throws {
        let date = try #require(VulcanDate.day("2026-01-31"))
        #expect(VulcanDate.dateString(VulcanDate.addDays(date, 1)) == "2026-02-01")
    }
}

struct ModelDecodingTests {
    @Test("Decodes PascalCase keys into lowerCamelCase properties")
    func decodesPascalCase() throws {
        let data = Data(#"{"Code":0,"Message":"OK"}"#.utf8)
        let status = try JSONDecoder.vulcan().decode(ApiStatus.self, from: data)
        #expect(status.code == 0)
        #expect(status.message == "OK")
    }

    @Test("Decodes a nested Hebe envelope")
    func decodesEnvelope() throws {
        let json = #"{"Status":{"Code":0,"Message":"OK"},"Envelope":[{"Id":1,"Key":"K","PupilId":2,"ContentRaw":"5","Content":"5","Comment":"","Value":5,"CreatedAt":"2026-10-20T09:00:00","ModifiedAt":"2026-10-20T09:00:00","Column":{"Id":1,"Name":"Sprawdzian","Subject":{"Id":7,"Name":"Matematyka"},"Category":{"Id":2,"Name":"Sprawdzian"}}}]}"#
        let box = try JSONDecoder.vulcan().decode(EnvelopeBox<[Grade]>.self, from: Data(json.utf8))
        #expect(box.status.code == 0)
        #expect(box.envelope?.first?.column.subject.name == "Matematyka")
        #expect(box.envelope?.first?.numericValue == 5.0)
    }
}

struct FormattingTests {
    @Test("Grade values are formatted for Polish readers")
    func cleanDouble() {
        #expect(4.0.clean == "4")
        #expect(5.5.clean == "5,50")
    }

    @Test("Message boxes have Polish labels")
    func messageKindLabels() {
        #expect(MessageKind.received.rawValue == "Odebrane")
        #expect(MessageKind.allCases.count == 3)
    }
}
