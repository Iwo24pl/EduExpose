import Foundation

/// The electronic register a stored student belongs to.
///
/// The provider is a property of the account, not of the screen. One app
/// install can hold eduVULCAN and Librus accounts at the same time.
enum EduRegistry: String, Codable, CaseIterable, Identifiable, Sendable {
    case eduVulcan = "eduvulcan"
    case librus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eduVulcan: return "eduVULCAN"
        case .librus: return "Librus"
        }
    }

    /// Short secondary label used under the provider name in the picker.
    var subtitle: String {
        switch self {
        case .eduVulcan: return "VULCAN"
        case .librus: return "Synergia"
        }
    }

    /// The first credential field is a login for eduVULCAN and an e-mail
    /// (Konto LIBRUS) for Librus.
    var loginFieldLabel: String {
        switch self {
        case .eduVulcan: return "Login"
        case .librus: return "E-mail"
        }
    }

    var loginPlaceholder: String {
        switch self {
        case .eduVulcan: return "Login lub e-mail"
        case .librus: return "E-mail Konto LIBRUS"
        }
    }

    /// The web-cookie Librus flow exposes one student per session. The
    /// multi-child importer is a separate, opt-in follow-up.
    var supportsMultipleStudentsPerLogin: Bool {
        switch self {
        case .eduVulcan: return true
        case .librus: return false
        }
    }
}
