import Foundation

/// Provider-specific secrets for one stored student.
///
/// This is the storage-neutral replacement for the old flat `StoredStudent`
/// fields. The legacy initializer in `RegistryStudent` keeps existing
/// Keychain blobs readable while the UI integration is still pending.
struct EduVulcanSession: Codable, Sendable {
    var credential: HebeCredential
    var restURL: String
    var tenant: String?
    var login: String?
    var password: String?
}

enum RegistrySession: Codable, Sendable {
    case eduVulcan(EduVulcanSession)
    case librus(LibrusSession)

    private enum CodingKeys: String, CodingKey {
        case provider
        case eduVulcan
        case librus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawProvider = try container.decode(String.self, forKey: .provider)
        switch rawProvider.lowercased() {
        case EduRegistry.eduVulcan.rawValue, "eduvulcan":
            self = .eduVulcan(try container.decode(EduVulcanSession.self, forKey: .eduVulcan))
        case EduRegistry.librus.rawValue:
            self = .librus(try container.decode(LibrusSession.self, forKey: .librus))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .provider,
                in: container,
                debugDescription: "Unknown registry provider: \(rawProvider)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .eduVulcan(let session):
            try container.encode(EduRegistry.eduVulcan.rawValue, forKey: .provider)
            try container.encode(session, forKey: .eduVulcan)
        case .librus(let session):
            try container.encode(EduRegistry.librus.rawValue, forKey: .provider)
            try container.encode(session, forKey: .librus)
        }
    }
}

/// A stored student after the provider split.
///
/// `session` is the only place secrets live. Views keep reading the
/// provider-neutral `Account` profile.
struct RegistryStudent: Codable, Identifiable, Sendable {
    var id: String
    var provider: EduRegistry
    var account: Account
    var session: RegistrySession
    var isEnabled: Bool

    var displayName: String { account.displayName }
    var schoolName: String { account.schoolName }

    var eduVulcanSession: EduVulcanSession? {
        guard case let .eduVulcan(session) = session else { return nil }
        return session
    }

    var librusSession: LibrusSession? {
        guard case let .librus(session) = session else { return nil }
        return session
    }

    /// The old flat model is still the input shape of `HebeClient` and the
    /// eduVULCAN mail client, so the adapter lives next to the migration.
    var legacyStoredStudent: StoredStudent? {
        guard let session = eduVulcanSession else { return nil }
        return StoredStudent(
            id: id,
            account: account,
            credential: session.credential,
            restUrl: session.restURL,
            login: session.login,
            password: session.password,
            tenant: session.tenant,
            isEnabled: isEnabled
        )
    }
}

extension RegistryStudent {
    /// Maps a Keychain entry written by EduExpose 1.x. Those entries only
    /// ever contained eduVULCAN/Hebe accounts, so the provider is implicit.
    init(legacy: StoredStudent) {
        self.init(
            id: legacy.id,
            provider: .eduVulcan,
            account: legacy.account,
            session: .eduVulcan(EduVulcanSession(
                credential: legacy.credential,
                restURL: legacy.restUrl,
                tenant: legacy.tenant,
                login: legacy.login,
                password: legacy.password
            )),
            isEnabled: legacy.isEnabled
        )
    }
}
