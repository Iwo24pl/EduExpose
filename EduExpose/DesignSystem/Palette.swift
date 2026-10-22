import SwiftUI
import UIKit

/// Colour parsed from a hex string, kept free of SwiftUI so it can be tested.
struct SRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let black = SRGB(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let raw = UInt32(value, radix: 16) else {
            return nil
        }

        red = Double((raw >> 16) & 0xFF) / 255
        green = Double((raw >> 8) & 0xFF) / 255
        blue = Double(raw & 0xFF) / 255
    }
}

extension Color {
    init(srgb: SRGB) {
        self.init(.sRGB, red: srgb.red, green: srgb.green, blue: srgb.blue, opacity: 1)
    }

    init(hex: String) {
        self.init(srgb: SRGB(hex: hex) ?? .black)
    }
}

/// Material 3 olive palette carried over from the Compose app.
enum Palette {
    static let primary = adaptive("4C662B", "B1D18A")
    static let onPrimary = adaptive("FFFFFF", "1F3701")
    static let primaryContainer = adaptive("CDEDA3", "354E16")
    static let onPrimaryContainer = adaptive("354E16", "CDEDA3")

    static let secondaryContainer = adaptive("DCE7C8", "404A33")
    static let tertiaryContainer = adaptive("BCECE7", "1F4E4B")

    static let background = adaptive("F9FAEF", "12140E")
    static let surfaceContainer = adaptive("EEEFE3", "1E201A")
    static let onSurface = adaptive("1A1C16", "E2E3D8")
    static let onSurfaceVariant = adaptive("44483D", "C5C8BA")
    static let outline = adaptive("75796C", "8F9285")
    static let error = adaptive("BA1A1A", "FFB4AB")

    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: String) -> UIColor {
        let rgb = SRGB(hex: hex) ?? .black
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

/// Soft olive wash behind glass surfaces.
struct ScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Palette.background,
                Palette.primaryContainer.opacity(0.35),
                Palette.tertiaryContainer.opacity(0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
