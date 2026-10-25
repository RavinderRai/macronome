import SwiftUI

/// Colors and type from docs/design/v2-app (Instrument, dark, amber).
enum Theme {
    static let graphite = Color(hex: 0x111210)
    static let surface = Color(hex: 0x1A1B19)
    static let bar = Color(hex: 0x232421)
    static let raised = Color(hex: 0x2A2C28)
    static let text = Color(hex: 0xEDEDE8)
    static let text2 = Color(hex: 0xB4B6AE)
    static let text3 = Color(hex: 0x9A9C95)
    static let muted = Color(hex: 0xA3A69E)
    static let hairline = Color(hex: 0x2A2B28)
    static let track = Color(hex: 0x2C2D2A)
    static let tick = Color(hex: 0x5A5C56)
    /// The mic, protein, focus. Nothing else.
    static let amber = Color(hex: 0xFFB547)
    /// Only the listening panel, the confirmation card and the row just logged.
    static let deepAmber = Color(hex: 0x2B1F0E)
    static let deepAmber2 = Color(hex: 0x3A2A14)
    static let amberDivider = Color(hex: 0x4A3518)
    static let amberText = Color(hex: 0xC9CBC4)
    /// Over target only.
    static let coral = Color(hex: 0xFF7A66)
    static let fat = Color(hex: 0x7F827A)
    static let planned = Color(hex: 0xCFD1C9)

    static func color(for key: MacroStatus.Key) -> Color {
        switch key {
        case .protein: amber
        case .carbs: text
        case .fat: fat
        default: text
        }
    }
}

/// Geist stands in as SF Pro and Geist Mono as SF Mono until the Geist font files are
/// bundled; swap the two families here.
enum Typo {
    static func numeral(_ size: CGFloat = 100) -> Font { .system(size: size, weight: .medium) }
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold) }
    static let row = Font.system(size: 16, weight: .medium)
    static let body = Font.system(size: 15)
    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let cap = Font.system(size: 11, weight: .medium, design: .monospaced)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension View {
    /// Mono caps label: "BREAKFAST · 272".
    func capStyle(_ color: Color = Theme.text3) -> some View {
        font(Typo.cap).tracking(0.9).textCase(.uppercase).foregroundStyle(color)
    }

    func numeralStyle(_ size: CGFloat = 100) -> some View {
        font(Typo.numeral(size)).tracking(-size * 0.055).monospacedDigit()
    }
}

/// Diagonal hatching for planned amounts.
struct Hatch: View {
    var color: Color = Theme.text
    var spacing: CGFloat = 5
    var lineWidth: CGFloat = 1.5
    var outlined = true

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
            if outlined {
                ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)), with: .color(color), lineWidth: 1)
            }
        }
        .clipped()
    }
}
