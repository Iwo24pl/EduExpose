import Foundation

/// Signs in to one electronic register and returns the accounts it exposes.
///
/// Implementations must not persist credentials themselves; the caller
/// stores the returned `RegistryStudent.session` in the Keychain.
protocol RegistryAuthService: Sendable {
    var provider: EduRegistry { get }
    func signIn(login: String, password: String) async throws -> [RegistryStudent]
}

/// eduVULCAN sign-in through the existing Prometheus/Hebe implementation.
struct PrometheusAuthService: RegistryAuthService {
    let session: URLSession

    var provider: EduRegistry { .eduVulcan }

    func signIn(login: String, password: String) async throws -> [RegistryStudent] {
        let found = try await PrometheusLoginService(session: session)
            .signIn(login: login, password: password)
        return found.map { RegistryStudent(legacy: $0) }
    }
}
