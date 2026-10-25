import Testing

@testable import EduExpose

struct AppVersionTests {
    @Test("Treats v1.0.0 and 1.0.0 as the same release")
    func ignoresPrefixAndPatch() throws {
        let tagged = try #require(AppVersion("v1.0.0"))
        let bundle = try #require(AppVersion("1.0.0"))
        let short = try #require(AppVersion("1.0"))

        #expect(tagged == bundle)
        #expect(short == bundle)
        #expect(!(tagged < bundle))
        #expect(!(bundle < tagged))
    }

    @Test("Compares numeric parts by value")
    func comparesNumerically() throws {
        let older = try #require(AppVersion("1.9.9"))
        let newer = try #require(AppVersion("1.10.0"))
        let major = try #require(AppVersion("v2"))

        #expect(older < newer)
        #expect(newer < major)
    }

    @Test("Orders prereleases below the final release")
    func ordersPrereleases() throws {
        let beta2 = try #require(AppVersion("1.0.0-beta.2"))
        let beta11 = try #require(AppVersion("1.0.0-beta.11"))
        let final = try #require(AppVersion("1.0.0"))

        #expect(beta2 < beta11)
        #expect(beta11 < final)
    }

    @Test("Ignores build metadata")
    func ignoresBuildMetadata() throws {
        let withBuild = try #require(AppVersion("1.0.0+43"))
        let plain = try #require(AppVersion("1.0.0"))

        #expect(withBuild == plain)
    }

    @Test("Rejects tags that are not versions")
    func rejectsNonVersions() {
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("ci-logs") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("1.x.0") == nil)
    }

    @Test("Picks the highest stable release regardless of API order")
    func picksHighestStableRelease() throws {
        let releases = [
            AppRelease(tagName: "latest", htmlURL: "https://example.com/latest", prerelease: true),
            AppRelease(tagName: "v1.0.0", htmlURL: "https://example.com/1.0.0", prerelease: false),
            AppRelease(tagName: "v1.2.0", htmlURL: "https://example.com/1.2.0", prerelease: false),
            AppRelease(tagName: "v1.1.0", htmlURL: "https://example.com/1.1.0", prerelease: false)
        ]
        let current = try #require(AppVersion("1.0.0"))
        let newest = try #require(
            AppReleasePicker.newest(in: releases, current: current)
        )

        #expect(newest.release.tagName == "v1.2.0")
        #expect(current < newest.version)
    }

    @Test("Does not treat the current release as an update")
    func currentReleaseIsNotNewer() throws {
        let releases = [
            AppRelease(tagName: "v1.0.0", htmlURL: "https://example.com/1.0.0", prerelease: false)
        ]
        let current = try #require(AppVersion("1.0.0"))
        let newest = try #require(
            AppReleasePicker.newest(in: releases, current: current)
        )

        #expect(!(current < newest.version))
    }

    @Test("A stable build ignores newer prereleases")
    func stableBuildIgnoresPrereleases() throws {
        let releases = [
            AppRelease(
                tagName: "v1.1.0-beta.2",
                htmlURL: "https://example.com/1.1.0-beta.2",
                prerelease: true
            ),
            AppRelease(tagName: "v1.0.0", htmlURL: "https://example.com/1.0.0", prerelease: false)
        ]
        let current = try #require(AppVersion("1.0.0"))
        let newest = try #require(
            AppReleasePicker.newest(in: releases, current: current)
        )

        #expect(newest.release.tagName == "v1.0.0")
    }

    @Test("A prerelease build can see newer prereleases")
    func prereleaseBuildSeesPrereleases() throws {
        let releases = [
            AppRelease(
                tagName: "v1.1.0-beta.2",
                htmlURL: "https://example.com/1.1.0-beta.2",
                prerelease: true
            ),
            AppRelease(tagName: "v1.0.0", htmlURL: "https://example.com/1.0.0", prerelease: false)
        ]
        let current = try #require(AppVersion("1.1.0-beta.1"))
        let newest = try #require(
            AppReleasePicker.newest(in: releases, current: current)
        )

        #expect(newest.release.tagName == "v1.1.0-beta.2")
        #expect(current < newest.version)
    }
}
