import Foundation

/// Only the hosts the backend is allowed to talk to. There is no wildcard:
/// credentials and cookies must never follow a server-controlled redirect
/// somewhere else.
enum LibrusHosts {
    static let allowed: Set<String> = [
        "synergia.librus.pl",
        "api.librus.pl",
        "portal.librus.pl",
        "wiadomosci.librus.pl",
        "sandbox.librus.pl"
    ]

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return allowed.contains(host)
    }

    static func resolve(_ location: String, relativeTo base: URL) -> URL? {
        guard let url = URL(string: location, relativeTo: base)?.absoluteURL,
              isAllowed(url) else {
            return nil
        }
        return url
    }

    static func isSynergia(_ domain: String) -> Bool {
        let value = domain.lowercased()
        return value == "synergia.librus.pl" || value.hasSuffix(".synergia.librus.pl")
    }

    static func isDataGateway(_ url: URL) -> Bool {
        url.host?.lowercased() == "synergia.librus.pl"
            && url.path.hasPrefix("/gateway/api/2.0")
    }

    static func isMessages(_ url: URL) -> Bool {
        url.host?.lowercased() == "wiadomosci.librus.pl"
    }
}
