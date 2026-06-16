import SwiftUI
import CoreText

/// Paleta cianótipo da blueprint — fundo azul, traço branco, acento molten.
enum BP {
    static let bg      = Color(hex: 0x0E2F63)
    static let bg2     = Color(hex: 0x15407E)
    static let bgDeep  = Color(hex: 0x0A2750)
    static let panel   = Color(hex: 0x0A2348)

    static let line     = Color(hex: 0xFFFFFF)
    static let lineDim   = Color(hex: 0x9FC0EC)
    static let ink       = Color(hex: 0xF6FAFF)
    static let inkDim     = Color(hex: 0xAEC6E8)
    static let inkFaint   = Color(hex: 0x7396C6)
    static let grid       = Color(hex: 0xAAC8F5, alpha: 0.10)

    static let accent      = Color(hex: 0xFF8A4C)   // molten — só estados ativos
    static let accentSoft  = Color(hex: 0xFFC39A)

    static let sheet = LinearGradient(
        colors: [bg2, bg, bgDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let mono = Font.system(.body, design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Fontes próprias (registradas em runtime — ver FontRegistry).
    /// Londrina Outline — títulos em contorno, casa com o traço da blueprint.
    static func display(_ size: CGFloat) -> Font { .custom("LondrinaOutline-Regular", size: size) }
    /// Fraunces (serif com caráter) — para o tom de "patente".
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let heavy = [Font.Weight.bold, .heavy, .black].contains(weight)
        return .custom(heavy ? "Fraunces72pt-Black" : "Fraunces72pt-SemiBold", size: size)
    }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("Fraunces72pt-Italic", size: size) }
    static func serifRegular(_ size: CGFloat) -> Font { .custom("Fraunces72pt-Regular", size: size) }
}

/// Registra as fontes empacotadas (.ttf em Resources) no processo, no launch.
enum FontRegistry {
    static func register() {
        guard let resPath = Bundle.main.resourcePath,
              let enumerator = FileManager.default.enumerator(atPath: resPath) else { return }
        for case let file as String in enumerator where file.hasSuffix(".ttf") {
            let url = URL(fileURLWithPath: resPath).appendingPathComponent(file)
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Paleta da forja — derivada direto do spec do Anvil.
enum Forge {
    static let bg       = Color(hex: 0x0E0F13)
    static let bgElev   = Color(hex: 0x16181F)
    static let bgElev2  = Color(hex: 0x1D2029)
    static let line     = Color(hex: 0x262A35)

    static let ink      = Color(hex: 0xE8E6E1)
    static let inkDim    = Color(hex: 0xA7A39A)
    static let inkFaint  = Color(hex: 0x6F6B62)

    static let molten     = Color(hex: 0xFF7A3C)
    static let moltenSoft = Color(hex: 0xFFB784)
    static let ember      = Color(hex: 0xE23D2F)
    static let steel      = Color(hex: 0x7FB4D4)
    static let good       = Color(hex: 0x5FC98A)
    static let warn       = Color(hex: 0xE9C46A)

    /// Gradiente de metal quente — usado em destaques e no brilho da brasa.
    static let moltenGradient = LinearGradient(
        colors: [molten, ember],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let mono = Font.system(.body, design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
