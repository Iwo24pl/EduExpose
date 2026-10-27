import Foundation

// MARK: - Flexible scalars

/// Librus is inconsistent: most ids are integers, but timetable lessons,
//. school notices and some attendances use strings. Decode both and keep a
/// stable non-negative integer for the existing UI models.
struct LibrusID: Decodable, Hashable, Sendable, CustomStringConvertible {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            raw = String(value)
        } else if let value = try? container.decode(String.self) {
            raw = value
        } else {
            throw DecodingError.typeMismatch(
                LibrusID.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an integer or string id"
                )
            )
        }
    }

    var int: Int? { Int(raw) }

    var stableInt: Int { int ?? Self.stableHash(raw) }

    var description: String { raw }

    static func stableHash(_ text: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash) & Int.max
    }
}

struct LibrusReference: Decodable, Hashable, Sendable {
    let id: LibrusID

    init(id: LibrusID) {
        self.id = id
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let id = try? container.decode(LibrusID.self) {
            self.id = id
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LibrusID.self, forKey: .id)
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }
}

struct LibrusNameReference: Decodable, Sendable {
    let id: LibrusID
    let name: String?
    let symbol: String?
}

/// A weight or average may arrive as a number or as a numeric string.
struct LibrusNumber: Decodable, Sendable, Equatable {
    let raw: String?
    let value: Double?

    init(raw: String?, value: Double?) {
        self.raw = raw
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self.raw = nil
            self.value = value
            return
        }
        if let value = try? container.decode(String.self) {
            raw = value
            self.value = Double(value.replacingOccurrences(of: ",", with: "."))
            return
        }
        throw DecodingError.typeMismatch(
            LibrusNumber.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a number or numeric string"
            )
        )
    }
}

// MARK: - Identity and school

struct LibrusMeEnvelope: Decodable {
    let me: LibrusMe?
}

struct LibrusMe: Decodable {
    let account: LibrusLoginAccount?
    let user: LibrusStudentUser?
}

struct LibrusLoginAccount: Decodable {
    let id: LibrusID?
    let userId: LibrusID?
    let schoolId: LibrusID?
    let firstName: String?
    let lastName: String?
    let email: String?
}

struct LibrusStudentUser: Decodable {
    let id: LibrusID?
    let firstName: String?
    let lastName: String?
}

struct LibrusSchoolEnvelope: Decodable {
    let school: LibrusSchool?
}

struct LibrusSchool: Decodable {
    let id: LibrusID?
    let name: String?
    let town: String?
}

struct LibrusClassesEnvelope: Decodable {
    let schoolClass: LibrusClass?

    private enum CodingKeys: String, CodingKey {
        case schoolClass = "class"
    }
}

struct LibrusClass: Decodable {
    let id: LibrusID?
    let unitId: LibrusID?
    let number: String?
    let symbol: String?
    let beginSchoolYear: String?
    let endFirstSemester: String?
    let endSchoolYear: String?
}

struct LibrusUserProfileEnvelope: Decodable {
    let userProfile: LibrusUserProfile?
}

struct LibrusUserProfile: Decodable {
    let classNumber: String?
    let accountType: String?
}

struct LibrusUserEnvelope: Decodable {
    let user: LibrusUser?
}

struct LibrusUser: Decodable {
    let id: LibrusID?
    let firstName: String?
    let lastName: String?
    let classRegisterNumber: LibrusID?
}

// MARK: - Lookups

struct LibrusSubjectsEnvelope: Decodable {
    let subjects: [LibrusSubject]?
}

struct LibrusSubject: Decodable {
    let id: LibrusID
    let name: String
    let short: String?
}

struct LibrusUsersEnvelope: Decodable {
    let users: [LibrusUser]?
}

struct LibrusClassroomsEnvelope: Decodable {
    let classrooms: [LibrusClassroom]?
}

struct LibrusClassroom: Decodable {
    let id: LibrusID
    let name: String?
    let symbol: String?
}

// MARK: - Grades

struct LibrusGradesEnvelope: Decodable {
    let grades: [LibrusGrade]?
}

struct LibrusGrade: Decodable {
    let id: LibrusID
    let grade: String?
    let subject: LibrusReference?
    let category: LibrusReference?
    let semester: Int?
    let addDate: String?
    let comments: [LibrusReference]?
    let addedBy: LibrusReference?
}

struct LibrusGradeCategoriesEnvelope: Decodable {
    let categories: [LibrusGradeCategory]?
}

struct LibrusGradeCategory: Decodable {
    let id: LibrusID
    let name: String
    let weight: LibrusNumber?
}

struct LibrusCommentsEnvelope: Decodable {
    let comments: [LibrusComment]?
}

struct LibrusComment: Decodable {
    let id: LibrusID
    let text: String?
}

struct LibrusAveragesEnvelope: Decodable {
    let averages: [String: LibrusNumber]?
}

// MARK: - Timetable

struct LibrusTimetableEnvelope: Decodable {
    let timetable: [String: [[LibrusLesson]]]?
}

struct LibrusLesson: Decodable {
    let lessonNo: LibrusID?
    let hourFrom: String?
    let hourTo: String?
    let subject: LibrusReference?
    let teacher: LibrusReference?
    let classroom: LibrusNameReference?
    let isCanceled: Bool?
    let isSubstitutionClass: Bool?
    let orgDate: String?
    let orgLessonNo: LibrusID?
    let substitutionNote: String?
}

// MARK: - Agenda and homework

struct LibrusHomeWorksEnvelope: Decodable {
    let homeWorks: [LibrusAgendaEvent]?
}

struct LibrusAgendaEvent: Decodable {
    let id: LibrusID
    let date: String?
    let timeFrom: String?
    let timeTo: String?
    let content: String?
    let category: LibrusReference?
    let subject: LibrusReference?
    let createdBy: LibrusReference?
}

struct LibrusHomeWorksCategoriesEnvelope: Decodable {
    let categories: [LibrusNameReference]?
}

struct LibrusHomeworkAssignmentsEnvelope: Decodable {
    let homeWorkAssignments: [LibrusHomeworkAssignment]?
}

struct LibrusHomeworkAssignment: Decodable {
    let id: LibrusID
    let date: String?
    let dueDate: String?
    let topic: String?
    let text: String?
    let teacher: LibrusReference?
    let subject: LibrusReference?
    let homeworkAssigmentFiles: [LibrusHomeworkFile]?
}

struct LibrusHomeworkFile: Decodable {
    let id: LibrusID?
    let name: String?
    let url: String?
}

// MARK: - Notes

struct LibrusNotesEnvelope: Decodable {
    let notes: [LibrusNote]?
}

struct LibrusNote: Decodable {
    let id: LibrusID
    let text: String?
    let date: String?
    let positive: Int?
    let category: LibrusReference?
    let teacher: LibrusReference?
}

struct LibrusNotesCategoriesEnvelope: Decodable {
    let categories: [LibrusNoteCategory]?
}

struct LibrusNoteCategory: Decodable {
    let id: LibrusID
    let categoryName: String?
}

// MARK: - Announcements and lucky number

struct LibrusSchoolNoticesEnvelope: Decodable {
    let schoolNotices: [LibrusSchoolNotice]?
}

struct LibrusSchoolNotice: Decodable {
    let id: LibrusID
    let subject: String?
    let content: String?
    let startDate: String?
    let endDate: String?
    let creationDate: String?
    let wasRead: Bool?
}

struct LibrusLuckyNumbersEnvelope: Decodable {
    let luckyNumber: LibrusLuckyNumber?
}

struct LibrusLuckyNumber: Decodable {
    let luckyNumber: Int?
    let luckyNumberDay: String?
}

// MARK: - Messages

struct LibrusUnreadEnvelope: Decodable {
    let data: LibrusUnread?
}

struct LibrusUnread: Decodable {
    let inbox: Int?
    let notes: Int?
    let alerts: Int?
    let substitutions: Int?
    let absences: Int?
    let justifications: Int?
    let trash: Int?
}

struct LibrusMessageListEnvelope: Decodable, Sendable {
    let data: [LibrusMessageSummary]?
    let total: Int?
}

struct LibrusMessageSummary: Decodable, Sendable {
    let messageId: LibrusID?
    let senderName: String?
    let senderFirstName: String?
    let senderLastName: String?
    let receiverName: String?
    let receiverFirstName: String?
    let receiverLastName: String?
    let topic: String?
    let content: String?
    let sendDate: String?
    let readDate: String?
    let isAnyFileAttached: Bool?
}

struct LibrusMessageEnvelope: Decodable {
    let data: LibrusMessageDetail?
}

struct LibrusMessageDetail: Decodable {
    let messageId: LibrusID?
    let senderName: String?
    let topic: String?
    let sendDate: String?
    let message: String?
    let attachments: [LibrusMessageAttachment]?
    let receivers: [LibrusMessageReceiver]?
    let isMessageWithdrawn: Bool?
    let enableMessageWithdrawn: Bool?
}

struct LibrusMessageAttachment: Decodable {
    let id: LibrusID?
    let filename: String?
}

struct LibrusMessageReceiver: Decodable {
    let firstName: String?
    let lastName: String?
    let group: String?
    let readed: String?
}
