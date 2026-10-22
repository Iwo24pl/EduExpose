import Testing

@testable import EduExpose

struct SRGBTests {
    @Test("Parses a hash-prefixed colour")
    func parsesHashPrefixedHex() throws {
        let colour = try #require(SRGB(hex: "#4C662B"))

        #expect(abs(colour.red - 76.0 / 255.0) < 0.0001)
        #expect(abs(colour.green - 102.0 / 255.0) < 0.0001)
        #expect(abs(colour.blue - 43.0 / 255.0) < 0.0001)
    }

    @Test("Parses a colour without the hash")
    func parsesBareHex() throws {
        let colour = try #require(SRGB(hex: "F9FAEF"))

        #expect(abs(colour.red - 249.0 / 255.0) < 0.0001)
        #expect(abs(colour.green - 250.0 / 255.0) < 0.0001)
        #expect(abs(colour.blue - 239.0 / 255.0) < 0.0001)
    }

    @Test("Rejects malformed colours", arguments: ["", "#12", "GGGGGG", "#GGGGGG", "#4C662"])
    func rejectsMalformedHex(value: String) {
        #expect(SRGB(hex: value) == nil)
    }
}
