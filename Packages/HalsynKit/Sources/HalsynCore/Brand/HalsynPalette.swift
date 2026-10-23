import Foundation

/// Color en sRGB definido por su valor hexadecimal. Es la única fuente de los
/// valores de color de la marca; la capa SwiftUI los traduce a `Color`.
public struct HalsynRGBColor: Hashable, Sendable {
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
    public func contrastRatio(with other: HalsynRGBColor) -> Double {
        let l1 = relativeLuminance, l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

/// Paleta base de HÅLSYN (referencia visual aprobada).
public enum HalsynPalette {
    // Marca
    public static let deepGreen = HalsynRGBColor(hex: 0x0E2D2A)
    public static let turquoise = HalsynRGBColor(hex: 0x1FB99A)
    public static let mint = HalsynRGBColor(hex: 0xA7E5C9)
    public static let warmWhite = HalsynRGBColor(hex: 0xF7F8F5)
    public static let textDark = HalsynRGBColor(hex: 0x2E4441)
    public static let textLight = HalsynRGBColor(hex: 0xE8F6F1)

    // Modo oscuro
    public static let darkBackground = HalsynRGBColor(hex: 0x081B1A)
    public static let darkSurface = HalsynRGBColor(hex: 0x103330)
    public static let darkPrimary = HalsynRGBColor(hex: 0x072B26)
    public static let darkSecondary = HalsynRGBColor(hex: 0x1ED1A6)
    public static let darkAccent = HalsynRGBColor(hex: 0x5FECCF)

    // Complementos derivados para accesibilidad (no forman parte de la referencia).
    /// Turquesa oscurecido para texto y glifos pequeños sobre fondos claros:
    /// el turquesa de marca no alcanza 4,5:1 sobre blanco.
    public static let turquoiseInk = HalsynRGBColor(hex: 0x0D7A64)
    public static let surfaceLight = HalsynRGBColor(hex: 0xFFFFFF)
    public static let secondaryTextLight = HalsynRGBColor(hex: 0x5A6E6A)
    public static let secondaryTextDark = HalsynRGBColor(hex: 0x9DBDB4)
    public static let hairlineLight = HalsynRGBColor(hex: 0xE2E8E4)
    public static let hairlineDark = HalsynRGBColor(hex: 0x1C4541)

    // Estados (siempre acompañados de icono o texto, nunca solo color).
    public static let positiveLight = HalsynRGBColor(hex: 0x0D7A64)
    public static let positiveDark = HalsynRGBColor(hex: 0x5FECCF)
    public static let cautionLight = HalsynRGBColor(hex: 0x9A6200)
    public static let cautionDark = HalsynRGBColor(hex: 0xF2C14E)
    public static let alertLight = HalsynRGBColor(hex: 0xB3261E)
    public static let alertDark = HalsynRGBColor(hex: 0xFF8A80)
}

/// Token semántico con su variante clara y oscura.
public struct SemanticColor: Sendable {
    public let name: String
    public let light: HalsynRGBColor
    public let dark: HalsynRGBColor

    public init(_ name: String, light: HalsynRGBColor, dark: HalsynRGBColor) {
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

    // Gráficos (validados con el validador de paletas de dataviz; ver DESIGN_SYSTEM.md).
    /// Línea y barras principales: ≥ 3:1 sobre la superficie en ambos modos.
    public static let chartPrimary = SemanticColor("chartPrimary", light: HalsynRGBColor(hex: 0x14917A), dark: HalsynPalette.darkSecondary)
    /// Fases del sueño: rampa ordinal de un solo tono (más profundo = más intenso).
    public static let sleepAwake = SemanticColor("sleepAwake", light: HalsynRGBColor(hex: 0x5BBFAA), dark: HalsynRGBColor(hex: 0x0F7A6A))
    public static let sleepREM = SemanticColor("sleepREM", light: HalsynRGBColor(hex: 0x1E9C83), dark: HalsynRGBColor(hex: 0x1ED1A6))
    public static let sleepCore = SemanticColor("sleepCore", light: HalsynRGBColor(hex: 0x12705F), dark: HalsynRGBColor(hex: 0x7FE6CF))
    public static let sleepDeep = SemanticColor("sleepDeep", light: HalsynRGBColor(hex: 0x0B4440), dark: HalsynRGBColor(hex: 0xC8F5EA))

    /// Tokens que se usan como texto y deben cumplir WCAG AA (4,5:1) sobre
    /// `background` y `surface` en ambos modos. Verificado en tests.
    public static let textTokens: [SemanticColor] = [primaryText, secondaryText, accentText, positive, caution, alert]
}
