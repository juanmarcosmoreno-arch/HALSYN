#if canImport(SwiftUI)
import HalsynCore
import SwiftUI

/// Un color por zona cardíaca, el mismo en todas partes (reloj e iPhone):
/// gráfico en vivo, indicador de zona, campo ZONA, resumen, detalle de la
/// carrera, mapa por pulso y ajustes. De azul (Z1, suave) a rojo (Z5, máxima).
/// Se usan como relleno; los textos van en blanco o negro encima.
public enum HalsynZoneColors {
    public static let rgb: [HalsynRGBColor] = [
        HalsynRGBColor(hex: 0x5FA8D3), // Z1 muy suave
        HalsynRGBColor(hex: 0x1FB99A), // Z2 suave
        HalsynRGBColor(hex: 0xF2C14E), // Z3 moderada
        HalsynRGBColor(hex: 0xFF8A4C), // Z4 intensa
        HalsynRGBColor(hex: 0xFF5A4E), // Z5 máxima
    ]

    /// Color de la zona 1…5; por debajo de Z1 (0) o desconocida, gris.
    public static func color(_ zone: Int) -> Color {
        guard (1...5).contains(zone) else { return Color(HalsynPalette.secondaryTextDark) }
        return Color(rgb[zone - 1])
    }

    /// Texto legible sobre el color de la zona (negro en Z2–Z4, blanco en Z1 y Z5).
    public static func label(_ zone: Int) -> Color {
        (2...4).contains(zone) ? Color.black.opacity(0.85) : Color.white
    }
}

/// "Z3" sobre una cápsula del color de la zona.
public struct HalsynZoneBadge: View {
    private let zone: Int

    public init(zone: Int) {
        self.zone = zone
    }

    public var body: some View {
        Text(verbatim: zone == 0 ? "<Z1" : "Z\(zone)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(HalsynZoneColors.label(zone))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(HalsynZoneColors.color(zone)))
    }
}
#endif
