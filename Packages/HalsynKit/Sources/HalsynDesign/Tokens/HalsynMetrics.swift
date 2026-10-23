#if canImport(SwiftUI)
import SwiftUI

/// Escala de espaciado (múltiplos de 4 pt).
public enum HalsynSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    public static let xl: CGFloat = 28
    public static let xxl: CGFloat = 40
}

public enum HalsynRadius {
    public static let small: CGFloat = 10
    public static let tile: CGFloat = 18
    public static let card: CGFloat = 24
}

/// Tipografía: SF Pro del sistema basada en estilos de texto, para que respete
/// Dynamic Type. Los pesos ligeros evocan el logotipo.
extension Font {
    public static let halsynLargeTitle = Font.largeTitle.weight(.light)
    public static let halsynTitle = Font.title2.weight(.regular)
    public static let halsynHeadline = Font.headline.weight(.semibold)
    public static let halsynBody = Font.body
    public static let halsynCaption = Font.caption.weight(.medium)
    /// Etiquetas en mayúsculas con espaciado amplio (nombres de módulo).
    public static let halsynEyebrow = Font.caption2.weight(.semibold)
    /// Números de métricas en tarjetas.
    public static let halsynMetricValue = Font.title2.weight(.semibold).monospacedDigit()
}

extension View {
    /// Estilo de etiqueta de sección: mayúsculas, espaciado amplio, color secundario.
    public func halsynEyebrowStyle() -> some View {
        font(.halsynEyebrow)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.halsynSecondaryText)
    }

    /// Fondo base de pantalla de HÅLSYN.
    public func halsynScreenBackground() -> some View {
        background(Color.halsynBackground.ignoresSafeArea())
    }
}
#endif
