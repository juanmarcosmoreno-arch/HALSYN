#if canImport(SwiftUI)
import HalsynCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

extension Color {
    /// Color fijo de la paleta (no cambia con el modo claro/oscuro).
    public init(_ rgb: HalsynRGBColor, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    /// Color semántico que se adapta al modo claro u oscuro.
    /// En watchOS la interfaz es siempre oscura, así que se usa la variante oscura.
    public init(_ token: SemanticColor) {
        #if os(watchOS)
        self.init(token.dark)
        #elseif canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? token.dark : token.light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? token.dark : token.light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #else
        self.init(token.light)
        #endif
    }
}

/// Acceso a los tokens con sintaxis de estilo: `.foregroundStyle(.halsynPrimaryText)`.
extension ShapeStyle where Self == Color {
    public static var halsynBackground: Color { Color(HalsynColorTokens.background) }
    public static var halsynSurface: Color { Color(HalsynColorTokens.surface) }
    public static var halsynPrimaryText: Color { Color(HalsynColorTokens.primaryText) }
    public static var halsynSecondaryText: Color { Color(HalsynColorTokens.secondaryText) }
    public static var halsynAccent: Color { Color(HalsynColorTokens.accent) }
    public static var halsynAccentText: Color { Color(HalsynColorTokens.accentText) }
    public static var halsynAccentSoft: Color { Color(HalsynColorTokens.accentSoft) }
    public static var halsynHairline: Color { Color(HalsynColorTokens.hairline) }
    public static var halsynBrandDeep: Color { Color(HalsynColorTokens.brandDeep) }
    public static var halsynPositive: Color { Color(HalsynColorTokens.positive) }
    public static var halsynCaution: Color { Color(HalsynColorTokens.caution) }
    public static var halsynAlert: Color { Color(HalsynColorTokens.alert) }
    public static var halsynChart: Color { Color(HalsynColorTokens.chartPrimary) }
    public static var halsynHighlight: Color { Color(HalsynColorTokens.highlight) }
}

public enum HalsynGradients {
    /// Gradiente principal de anillos y énfasis.
    public static let brand = LinearGradient(
        colors: [Color(HalsynPalette.turquoise), Color(HalsynPalette.mint)],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    /// Gradiente angular para anillos de puntuación.
    public static let ring = AngularGradient(
        colors: [Color(HalsynPalette.turquoiseInk), Color(HalsynPalette.turquoise), Color(HalsynPalette.mint), Color(HalsynPalette.turquoise)],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    /// Acento cálido para lo extremo (puntuación baja, máxima intensidad).
    public static let ember = AngularGradient(
        colors: [Color(HalsynPalette.coral), Color(HalsynPalette.emberDark), Color(HalsynPalette.cautionDark), Color(HalsynPalette.emberDark)],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    /// Fondo de marca oscuro (iconos, splash, pantallas de reloj).
    public static let deep = LinearGradient(
        colors: [Color(HalsynPalette.darkSurface), Color(HalsynPalette.darkBackground)],
        startPoint: .top,
        endPoint: .bottom
    )
}
#endif
