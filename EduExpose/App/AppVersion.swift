import Foundation

/// Tolerant semantic version used to compare GitHub release tags (`v1.0.0`)
/// with the bundle's `CFBundleShortVersionString` (`1.0.0`).
///
/// Rules that matter for the update check:
/// - a leading `v`/`V` is ignored,
/// - `1.0` and `1.0.0` are equal,
/// - build metadata (`+43`) is ignored,
/// - prereleases (`1.0.0-beta.2`) sort below the final release,
/// - numeric components compare by value (`1.10.0` > `1.9.9`).
struct AppVersion: Comparable, Sendable {
    let components: [Int]
    let prerelease: [PrereleaseIdentifier]

    enum PrereleaseIdentifier: Comparable, Sendable {
        case number(Int)
        case text(String)

        static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.number(left), .number(right)):
                return left < right
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            case let (.text(left), .text(right)):
                return left < right
            }
        }
    }

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        // `+build` never changes precedence.
        if let plus = text.firstIndex(of: "+") {
            text = String(text[..<plus])
        }

        let parts = text.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let core = parts.first, !core.isEmpty else { return nil }

        var numbers: [Int] = []
        for component in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(component), number >= 0 else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { return nil }
        // `1.0.0` and `1.0` must be equal.
        while numbers.count > 1, numbers.last == 0 {
            numbers.removeLast()
        }

        var identifiers: [PrereleaseIdentifier] = []
        if parts.count == 2 {
            let prerelease = parts[1]
            guard !prerelease.isEmpty else { return nil }
            for component in prerelease.split(separator: ".", omittingEmptySubsequences: false) {
                guard !component.isEmpty else { return nil }
                if let number = Int(component) {
                    identifiers.append(.number(number))
                } else {
                    identifiers.append(.text(String(component).lowercased()))
                }
            }
        }

        components = numbers
        prerelease = identifiers
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components == rhs.components && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }

        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true):
            return false
        case (true, false):
            return false
        case (false, true):
            return true
        case (false, false):
            for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
                return left < right
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }
    }
}

/// The subset of a GitHub release payload used by the update check.
struct AppRelease: Decodable, Sendable {
    let tagName: String
    let htmlURL: String
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case prerelease
    }
}

enum AppReleasePicker {
    /// The highest version among the releases the current build may install.
    /// Stable builds ignore prereleases; prerelease builds see everything.
    static func newest(
        in releases: [AppRelease],
        current: AppVersion
    ) -> (release: AppRelease, version: AppVersion)? {
        let includePrereleases = !current.prerelease.isEmpty
        return releases
            .compactMap { release -> (release: AppRelease, version: AppVersion)? in
                guard includePrereleases || !release.prerelease,
                      let version = AppVersion(release.tagName) else {
                    return nil
                }
                return (release, version)
            }
            .max { $0.version < $1.version }
    }
}
