import Testing
import UIKit
@testable import EduExpose

struct AssetTests {
    @Test("The brand logo is bundled")
    func brandLogoExists() {
        #expect(UIImage(named: "BrandLogo") != nil)
    }

    @Test("The accent colour is bundled")
    func accentColorExists() {
        #expect(UIColor(named: "AccentColor") != nil)
    }
}
