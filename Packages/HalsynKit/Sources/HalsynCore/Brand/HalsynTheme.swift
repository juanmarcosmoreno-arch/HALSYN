import Foundation

/// Combinación de colores de la app de iPhone (fondo, superficies, texto y
/// acento), con su variante clara y oscura. Los colores de estado (bien,
/// atención, alerta), las zonas y el sueño no cambian con el tema.
///
/// Todos los temas cumplen WCAG AA (4,5:1) para texto sobre fondo y
/// superficie en ambos modos (ver tests).
public struct HalsynTheme: Identifiable, Hashable, Sendable {
    public struct Colors: Hashable, Sendable {
        public let background: HalsynRGBColor
        public let surface: HalsynRGBColor
        public let primaryText: HalsynRGBColor
        public let secondaryText: HalsynRGBColor
        public let accent: HalsynRGBColor
        public let accentText: HalsynRGBColor
        public let accentSoft: HalsynRGBColor
        public let hairline: HalsynRGBColor
        public let brandDeep: HalsynRGBColor
        public let chart: HalsynRGBColor

        public init(background: UInt32, surface: UInt32, primaryText: UInt32, secondaryText: UInt32, accent: UInt32, accentText: UInt32, accentSoft: UInt32, hairline: UInt32, brandDeep: UInt32, chart: UInt32) {
            self.background = HalsynRGBColor(hex: background)
            self.surface = HalsynRGBColor(hex: surface)
            self.primaryText = HalsynRGBColor(hex: primaryText)
            self.secondaryText = HalsynRGBColor(hex: secondaryText)
            self.accent = HalsynRGBColor(hex: accent)
            self.accentText = HalsynRGBColor(hex: accentText)
            self.accentSoft = HalsynRGBColor(hex: accentSoft)
            self.hairline = HalsynRGBColor(hex: hairline)
            self.brandDeep = HalsynRGBColor(hex: brandDeep)
            self.chart = HalsynRGBColor(hex: chart)
        }
    }

    public let id: String
    /// Clave de traducción.
    public let title: String
    public let light: Colors
    public let dark: Colors

    public static let halsyn = HalsynTheme(
        id: "halsyn", title: "HÅLSYN (turquesa)",
        light: Colors(background: 0xF7F8F5, surface: 0xFFFFFF, primaryText: 0x0E2D2A, secondaryText: 0x5A6E6A, accent: 0x1FB99A, accentText: 0x0D7A64, accentSoft: 0xA7E5C9, hairline: 0xE2E8E4, brandDeep: 0x0E2D2A, chart: 0x14917A),
        dark: Colors(background: 0x081B1A, surface: 0x103330, primaryText: 0xE8F6F1, secondaryText: 0x9DBDB4, accent: 0x1ED1A6, accentText: 0x5FECCF, accentSoft: 0x072B26, hairline: 0x1C4541, brandDeep: 0x072B26, chart: 0x1ED1A6)
    )
    public static let fjord = HalsynTheme(
        id: "fjord", title: "Fjord (azul)",
        light: Colors(background: 0xF4F7FA, surface: 0xFFFFFF, primaryText: 0x0F2233, secondaryText: 0x526170, accent: 0x2A7DE1, accentText: 0x1B5CAB, accentSoft: 0xD6E6FA, hairline: 0xDFE6EE, brandDeep: 0x0F2233, chart: 0x2369C2),
        dark: Colors(background: 0x08121D, surface: 0x112233, primaryText: 0xE6EEF7, secondaryText: 0x9DB2C7, accent: 0x4C9DFF, accentText: 0x8CC4FF, accentSoft: 0x0E2A47, hairline: 0x1E3550, brandDeep: 0x0E2A47, chart: 0x4C9DFF)
    )
    public static let lingon = HalsynTheme(
        id: "lingon", title: "Lingon (frambuesa)",
        light: Colors(background: 0xFAF6F6, surface: 0xFFFFFF, primaryText: 0x3A1218, secondaryText: 0x6B5659, accent: 0xD23A52, accentText: 0xA3243A, accentSoft: 0xF6D5DB, hairline: 0xEDE1E3, brandDeep: 0x3A1218, chart: 0xBF2E47),
        dark: Colors(background: 0x1A0C0F, surface: 0x2B1519, primaryText: 0xF7E9EB, secondaryText: 0xC9A9AE, accent: 0xFF5C75, accentText: 0xFF9AAA, accentSoft: 0x4A1A23, hairline: 0x43252B, brandDeep: 0x4A1A23, chart: 0xFF5C75)
    )
    public static let midnattssol = HalsynTheme(
        id: "midnattssol", title: "Midnattssol (ámbar)",
        light: Colors(background: 0xFBF8F2, surface: 0xFFFFFF, primaryText: 0x33240F, secondaryText: 0x6B5D4B, accent: 0xE08A2E, accentText: 0x93500E, accentSoft: 0xF7E2C4, hairline: 0xECE4D6, brandDeep: 0x33240F, chart: 0xB86A16),
        dark: Colors(background: 0x16110A, surface: 0x261D12, primaryText: 0xF7EEDF, secondaryText: 0xC7B497, accent: 0xFFA947, accentText: 0xFFC98A, accentSoft: 0x3D2C14, hairline: 0x3A2E1E, brandDeep: 0x3D2C14, chart: 0xFFA947)
    )
    public static let lavendel = HalsynTheme(
        id: "lavendel", title: "Lavendel (violeta)",
        light: Colors(background: 0xF7F6FB, surface: 0xFFFFFF, primaryText: 0x241B3A, secondaryText: 0x5F5970, accent: 0x7B5CD6, accentText: 0x5838B0, accentSoft: 0xE3DCF7, hairline: 0xE5E2EE, brandDeep: 0x241B3A, chart: 0x6A4BC9),
        dark: Colors(background: 0x0F0C1A, surface: 0x1C172C, primaryText: 0xEEEAF8, secondaryText: 0xB3AACB, accent: 0x9D82FF, accentText: 0xC3B2FF, accentSoft: 0x2C2250, hairline: 0x2E2845, brandDeep: 0x2C2250, chart: 0x9D82FF)
    )
    public static let skog = HalsynTheme(
        id: "skog", title: "Skog (verde bosque)",
        light: Colors(background: 0xF5F8F1, surface: 0xFFFFFF, primaryText: 0x1B2A14, secondaryText: 0x58634F, accent: 0x4E9A2F, accentText: 0x33701B, accentSoft: 0xDCEBCF, hairline: 0xE1E8DA, brandDeep: 0x1B2A14, chart: 0x3F8524),
        dark: Colors(background: 0x0C130A, surface: 0x172213, primaryText: 0xEAF3E3, secondaryText: 0xACBDA0, accent: 0x8BD45E, accentText: 0xAEE58C, accentSoft: 0x203517, hairline: 0x263822, brandDeep: 0x203517, chart: 0x8BD45E)
    )
    public static let grafit = HalsynTheme(
        id: "grafit", title: "Grafit (blanco y negro)",
        light: Colors(background: 0xF4F4F3, surface: 0xFFFFFF, primaryText: 0x1C1C1E, secondaryText: 0x5E5E62, accent: 0x3A3A3C, accentText: 0x2C2C2E, accentSoft: 0xE4E4E2, hairline: 0xE2E2E0, brandDeep: 0x1C1C1E, chart: 0x3A3A3C),
        dark: Colors(background: 0x0B0B0C, surface: 0x1C1C1E, primaryText: 0xF2F2F2, secondaryText: 0xAEAEB2, accent: 0xD8D8DA, accentText: 0xF2F2F2, accentSoft: 0x2C2C2E, hairline: 0x2C2C2E, brandDeep: 0x2C2C2E, chart: 0xD8D8DA)
    )

    public static let all: [HalsynTheme] = [.halsyn, .fjord, .lingon, .midnattssol, .lavendel, .skog, .grafit]

    public static func named(_ id: String?) -> HalsynTheme {
        all.first { $0.id == id } ?? .halsyn
    }

    public static let storageKey = "halsyn.theme"

    /// Tema en uso. Lo fija la app al arrancar y al cambiarlo en Perfil.
    nonisolated(unsafe) public static var current: HalsynTheme = .halsyn
}
