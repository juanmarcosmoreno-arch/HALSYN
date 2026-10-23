#if canImport(SwiftUI)
import HalsynCore
import SwiftUI

/// Geometría vectorial del símbolo Å-persona.
///
/// Es una reconstrucción aproximada de la referencia visual aprobada
/// (`Resources/Brand/reference/halsyn-brand-reference.png`), no el original.
/// Cuando el diseñador entregue el vector definitivo (SVG/PDF), debe sustituir
/// estas curvas. La misma geometría existe en `Resources/Brand/halsyn-symbol.svg`.
///
/// Capas (de atrás hacia delante):
/// 1. Lóbulo crema (hombro / curva superior de la A).
/// 2. Pierna izquierda en verde profundo (cuerpo en impulso).
/// 3. Torso translúcido turquesa, recortado a la pierna.
/// 4. Pierna derecha menta, semitransparente.
/// 5. Cabeza: círculo separado que es también el anillo de la Å.
public enum HalsynSymbolGeometry {
    /// Caja de diseño en el sistema de coordenadas de las curvas.
    public static let viewBox = CGRect(x: 24, y: 16, width: 520, height: 660)
    public static var aspectRatio: CGFloat { viewBox.width / viewBox.height }

    static let creamCenter = CGPoint(x: 215, y: 318)
    static let creamRadius: CGFloat = 135
    static let torsoCenter = CGPoint(x: 232, y: 290)
    static let torsoRadius: CGFloat = 140
    static let headCenter = CGPoint(x: 348, y: 103)
    static let headRadius: CGFloat = 82

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    static var cream: Path { circle(creamCenter, creamRadius) }
    static var torso: Path { circle(torsoCenter, torsoRadius) }
    static var head: Path { circle(headCenter, headRadius) }

    static var leftLeg: Path {
        var p = Path()
        p.move(to: CGPoint(x: 310, y: 220))
        p.addCurve(to: CGPoint(x: 380, y: 440), control1: CGPoint(x: 370, y: 225), control2: CGPoint(x: 385, y: 330))
        p.addCurve(to: CGPoint(x: 305, y: 430), control1: CGPoint(x: 360, y: 425), control2: CGPoint(x: 330, y: 415))
        p.addCurve(to: CGPoint(x: 265, y: 540), control1: CGPoint(x: 280, y: 445), control2: CGPoint(x: 268, y: 480))
        p.addCurve(to: CGPoint(x: 150, y: 670), control1: CGPoint(x: 262, y: 620), control2: CGPoint(x: 220, y: 670))
        p.addCurve(to: CGPoint(x: 32, y: 560), control1: CGPoint(x: 80, y: 670), control2: CGPoint(x: 30, y: 620))
        p.addCurve(to: CGPoint(x: 180, y: 360), control1: CGPoint(x: 35, y: 480), control2: CGPoint(x: 120, y: 420))
        p.addCurve(to: CGPoint(x: 310, y: 220), control1: CGPoint(x: 230, y: 305), control2: CGPoint(x: 260, y: 222))
        p.closeSubpath()
        return p
    }

    static var rightLeg: Path {
        var p = Path()
        p.move(to: CGPoint(x: 330, y: 213))
        p.addCurve(to: CGPoint(x: 530, y: 380), control1: CGPoint(x: 420, y: 195), control2: CGPoint(x: 500, y: 280))
        p.addCurve(to: CGPoint(x: 462, y: 522), control1: CGPoint(x: 548, y: 450), control2: CGPoint(x: 520, y: 518))
        p.addCurve(to: CGPoint(x: 377, y: 445), control1: CGPoint(x: 418, y: 525), control2: CGPoint(x: 395, y: 490))
        p.addCurve(to: CGPoint(x: 316, y: 300), control1: CGPoint(x: 357, y: 395), control2: CGPoint(x: 330, y: 350))
        p.addCurve(to: CGPoint(x: 330, y: 213), control1: CGPoint(x: 305, y: 255), control2: CGPoint(x: 310, y: 218))
        p.closeSubpath()
        return p
    }
}

/// Símbolo Å-persona de HÅLSYN.
public struct HalsynSymbol: View {
    public enum Style: Sendable {
        /// Gradientes de marca. Funciona sobre fondos claros y oscuros.
        case color
        /// Una sola tinta con opacidades por capa (marcas de agua, plantillas).
        case monochrome(Color)
    }

    private let style: Style

    public init(style: Style = .color) {
        self.style = style
    }

    public var body: some View {
        Canvas { context, size in
            let box = HalsynSymbolGeometry.viewBox
            let scale = min(size.width / box.width, size.height / box.height)
            context.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)

            switch style {
            case .color:
                Self.drawColor(in: &context)
            case .monochrome(let ink):
                Self.drawMonochrome(in: &context, ink: ink)
            }
        }
        .aspectRatio(HalsynSymbolGeometry.aspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: HalsynBrand.name))
        .accessibilityAddTraits(.isImage)
    }

    private static func stops(_ values: [(UInt32, Double)]) -> Gradient {
        Gradient(stops: values.map { Gradient.Stop(color: Color(RGBColor(hex: $0.0)), location: $0.1) })
    }

    private static func drawColor(in context: inout GraphicsContext) {
        typealias G = HalsynSymbolGeometry

        context.fill(G.cream, with: .linearGradient(
            stops([(0xF3F0E3, 0), (0xDDEBE0, 1)]),
            startPoint: CGPoint(x: 80, y: 183), endPoint: CGPoint(x: 350, y: 453)))

        context.fill(G.leftLeg, with: .linearGradient(
            stops([(0x08544C, 0), (0x0B8070, 0.55), (0x12C7A3, 1)]),
            startPoint: CGPoint(x: 85, y: 422), endPoint: CGPoint(x: 226, y: 670)))

        context.drawLayer { layer in
            layer.clip(to: G.leftLeg)
            layer.opacity = 0.75
            layer.fill(G.torso, with: .linearGradient(
                stops([(0x7FD3BC, 0), (0x1C9C87, 1)]),
                startPoint: CGPoint(x: 372, y: 150), endPoint: CGPoint(x: 92, y: 430)))
        }

        context.drawLayer { layer in
            layer.opacity = 0.9
            layer.fill(G.rightLeg, with: .linearGradient(
                stops([(0x8ADBBE, 0), (0xD3F4E3, 1)]),
                startPoint: CGPoint(x: 305, y: 205), endPoint: CGPoint(x: 540, y: 525)))
        }

        context.fill(G.head, with: .radialGradient(
            stops([(0x14998A, 0), (0xB8EDD8, 1)]),
            center: CGPoint(x: 332, y: 144), startRadius: 0, endRadius: 131))
    }

    private static func drawMonochrome(in context: inout GraphicsContext, ink: Color) {
        typealias G = HalsynSymbolGeometry
        context.fill(G.cream, with: .color(ink.opacity(0.25)))
        context.fill(G.leftLeg, with: .color(ink))
        context.drawLayer { layer in
            layer.clip(to: G.leftLeg)
            layer.fill(G.torso, with: .color(ink.opacity(0.7)))
        }
        context.fill(G.rightLeg, with: .color(ink.opacity(0.6)))
        context.fill(G.head, with: .color(ink))
    }
}

/// Logotipo HÅLSYN en texto: sans serif ligera con espaciado amplio.
public struct HalsynWordmark: View {
    private let size: CGFloat
    private let showsTagline: Bool

    public init(size: CGFloat = 34, showsTagline: Bool = false) {
        self.size = size
        self.showsTagline = showsTagline
    }

    public var body: some View {
        VStack(spacing: size * 0.28) {
            Text(verbatim: HalsynBrand.name)
                .font(.system(size: size, weight: .light))
                .tracking(size * 0.16)
            if showsTagline {
                Text(verbatim: HalsynBrand.tagline)
                    .font(.system(size: max(size * 0.26, 8), weight: .regular))
                    .tracking(size * 0.14)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .foregroundStyle(.halsynPrimaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: HalsynBrand.name))
    }
}

/// Composiciones del logotipo.
public struct HalsynLogo: View {
    public enum Layout: Sendable {
        case horizontal
        case vertical
        /// Símbolo + nombre pequeño, para barras de navegación.
        case compact
        case symbol
    }

    private let layout: Layout
    private let height: CGFloat

    public init(_ layout: Layout = .horizontal, height: CGFloat = 64) {
        self.layout = layout
        self.height = height
    }

    public var body: some View {
        switch layout {
        case .horizontal:
            HStack(spacing: height * 0.35) {
                HalsynSymbol().frame(height: height)
                HalsynWordmark(size: height * 0.42, showsTagline: true)
            }
        case .vertical:
            VStack(spacing: height * 0.3) {
                HalsynSymbol().frame(height: height)
                HalsynWordmark(size: height * 0.36, showsTagline: true)
            }
        case .compact:
            HStack(spacing: height * 0.3) {
                HalsynSymbol().frame(height: height)
                Text(verbatim: HalsynBrand.name)
                    .font(.system(size: height * 0.55, weight: .regular))
                    .tracking(height * 0.08)
                    .foregroundStyle(.halsynPrimaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: HalsynBrand.name))
        case .symbol:
            HalsynSymbol().frame(height: height)
        }
    }
}

/// Formas orgánicas decorativas de fondo, como en la referencia de marca.
/// Puramente decorativas: ocultas a VoiceOver.
public struct HalsynBackdrop: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                Ellipse()
                    .fill(Color.halsynAccentSoft.opacity(0.35))
                    .frame(width: w * 0.9, height: h * 0.45)
                    .rotationEffect(.degrees(-28))
                    .offset(x: w * 0.45, y: -h * 0.32)
                Ellipse()
                    .fill(Color.halsynAccent.opacity(0.12))
                    .frame(width: w * 0.8, height: h * 0.35)
                    .rotationEffect(.degrees(22))
                    .offset(x: -w * 0.5, y: h * 0.38)
            }
            .frame(width: w, height: h)
            .blur(radius: 30)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Símbolo") {
    VStack(spacing: 32) {
        HalsynLogo(.horizontal, height: 80)
        HalsynLogo(.vertical, height: 100)
        HStack(spacing: 24) {
            HalsynSymbol().frame(height: 48)
            HalsynSymbol(style: .monochrome(.halsynPrimaryText)).frame(height: 48)
            HalsynLogo(.compact, height: 28)
        }
    }
    .padding()
    .halsynScreenBackground()
}
#endif
