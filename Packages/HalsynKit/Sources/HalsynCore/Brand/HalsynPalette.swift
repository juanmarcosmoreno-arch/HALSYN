import Foundation

/// Color en sRGB definido por su valor hexadecimal. Es la única fuente de los
/// valores de color de la marca; la capa SwiftUI los traduce a `Color`.
public struct RGBColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    public var hexString: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Luminancia relativa según WCAG 2.x.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Relación de contraste WCAG entre dos colores (1...21).
    public func contrastRatio(with other: RGBColor) -> Double {
        let l1 = relativeLuminance, l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

/// Paleta base de HÅLSYN (referencia visual aprobada).
public enum HalsynPalette {
    // Marca
    public static let deepGreen = RGBColor(hex: 0x0E2D2A)
    public static let turquoise = RGBColor(hex: 0x1FB99A)
    public static let mint = RGBColor(hex: 0xA7E5C9)
    public static let warmWhite = RGBColor(hex: 0xF7F8F5)
    public static let textDark = RGBColor(hex: 0x2E4441)
    public static let textLight = RGBColor(hex: 0xE8F6F1)

    // Modo oscuro
    public static let darkBackground = RGBColor(hex: 0x081B1A)
    public static let darkSurface = RGBColor(hex: 0x103330)
    public static let darkPrimary = RGBColor(hex: 0x072B26)
    public static let darkSecondary = RGBColor(hex: 0x1ED1A6)
    public static let darkAccent = RGBColor(hex: 0x5FECCF)

    // Complementos derivados para accesibilidad (no forman parte de la referencia).
    /// Turquesa oscurecido para texto y glifos pequeños sobre fondos claros:
    /// el turquesa de marca no alcanza 4,5:1 sobre blanco.
    public static let turquoiseInk = RGBColor(hex: 0x0D7A64)
    public static let surfaceLight = RGBColor(hex: 0xFFFFFF)
    public static let secondaryTextLight = RGBColor(hex: 0x5A6E6A)
    public static let secondaryTextDark = RGBColor(hex: 0x9DBDB4)
    public static let hairlineLight = RGBColor(hex: 0xE2E8E4)
    public static let hairlineDark = RGBColor(hex: 0x1C4541)

    // Estados (siempre acompañados de icono o texto, nunca solo color).
    public static let positiveLight = RGBColor(hex: 0x0D7A64)
    public static let positiveDark = RGBColor(hex: 0x5FECCF)
    public static let cautionLight = RGBColor(hex: 0x9A6200)
    public static let cautionDark = RGBColor(hex: 0xF2C14E)
    public static let alertLight = RGBColor(hex: 0xB3261E)
    public static let alertDark = RGBColor(hex: 0xFF8A80)
}

/// Token semántico con su variante clara y oscura.
public struct SemanticColor: Sendable {
    public let name: String
    public let light: RGBColor
    public let dark: RGBColor

    public init(_ name: String, light: RGBColor, dark: RGBColor) {
        self.name = name
        self.light = light
        self.dark = dark
    }
}

/// Tokens semánticos. Las vistas usan estos nombres, nunca hexadecimales.
public enum HalsynColorTokens {
    public static let background = SemanticColor("background", light: HalsynPalette.warmWhite, dark: HalsynPalette.darkBackground)
    public static let surface = SemanticColor("surface", light: HalsynPalette.surfaceLight, dark: HalsynPalette.darkSurface)
    public static let primaryText = SemanticColor("primaryText", light: HalsynPalette.deepGreen, dark: HalsynPalette.textLight)
    public static let secondaryText = SemanticColor("secondaryText", light: HalsynPalette.secondaryTextLight, dark: HalsynPalette.secondaryTextDark)
    /// Acento para rellenos, anillos y gráficos.
    public static let accent = SemanticColor("accent", light: HalsynPalette.turquoise, dark: HalsynPalette.darkSecondary)
    /// Acento apto para texto.
    public static let accentText = SemanticColor("accentText", light: HalsynPalette.turquoiseInk, dark: HalsynPalette.darkAccent)
    public static let accentSoft = SemanticColor("accentSoft", light: HalsynPalette.mint, dark: HalsynPalette.darkPrimary)
    public static let hairline = SemanticColor("hairline", light: HalsynPalette.hairlineLight, dark: HalsynPalette.hairlineDark)
    public static let brandDeep = SemanticColor("brandDeep", light: HalsynPalette.deepGreen, dark: HalsynPalette.darkPrimary)
    public static let positive = SemanticColor("positive", light: HalsynPalette.positiveLight, dark: HalsynPalette.positiveDark)
    public static let caution = SemanticColor("caution", light: HalsynPalette.cautionLight, dark: HalsynPalette.cautionDark)
    public static let alert = SemanticColor("alert", light: HalsynPalette.alertLight, dark: HalsynPalette.alertDark)

    /// Tokens que se usan como texto y deben cumplir WCAG AA (4,5:1) sobre
    /// `background` y `surface` en ambos modos. Verificado en tests.
    public static let textTokens: [SemanticColor] = [primaryText, secondaryText, accentText, positive, caution, alert]
}
