import SwiftUI

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

/// Dark navy palette derived from the EduExpose app icon.
/// The app is intentionally dark-only; every colour below is fixed.
enum Palette {
    static let brandNavyDeep = Color(hex: "02091F")
    static let brandNavy = Color(hex: "031554")
    static let brandNavyLift = Color(hex: "062B72")
    static let brandBlue = Color(hex: "0085F8")
    static let brandBlueSoft = Color(hex: "4FA8FF")

    static let primary = brandBlueSoft
    static let onPrimary = Color(hex: "001A3D")
    static let primaryContainer = Color(hex: "0A2E6B")
    static let onPrimaryContainer = Color(hex: "D7E8FF")

    static let secondaryContainer = Color(hex: "0A2350")
    static let tertiaryContainer = Color(hex: "0B3C6E")

    static let background = brandNavyDeep
    static let surfaceContainer = Color(hex: "071B44")
    static let onSurface = Color(hex: "F3F7FF")
    static let onSurfaceVariant = Color(hex: "B7C7E6")
    static let outline = Color(hex: "6D84AE")
    static let error = Color(hex: "FFB4AB")
    static let success = Color(hex: "8BE0A4")
    static let warning = Color(hex: "FFD27A")
}

/// Dark navy wash behind glass surfaces.
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Palette.brandNavyDeep,
                    Palette.brandNavy,
                    Palette.brandNavyLift
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Palette.brandBlue.opacity(0.20),
                    Palette.brandBlue.opacity(0.04),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}
