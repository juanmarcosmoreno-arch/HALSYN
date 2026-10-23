#if canImport(SwiftUI)
import HalsynCore
import SwiftUI

/// Valor + unidad + título, sin contenedor. Bloque básico de las demás vistas.
public struct HalsynMetric: View {
    private let title: String
    private let value: String?
    private let unit: String
    private let alignment: HorizontalAlignment

    /// `value == nil` se muestra como "—" (sin dato), nunca como cero.
    public init(title: String, value: String?, unit: String, alignment: HorizontalAlignment = .leading) {
        self.title = title
        self.value = value
        self.unit = unit
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value ?? "—")
                    .font(.halsynMetricValue)
                    .foregroundStyle(.halsynPrimaryText)
                if value != nil, !unit.isEmpty {
                    Text(LocalizedStringKey(unit))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            Text(LocalizedStringKey(title))
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(halsynAccessibilityValue(value, unit: unit))
    }
}

/// Valor de accesibilidad "valor unidad" con la unidad localizada ("lpm" → "bpm").
func halsynAccessibilityValue(_ value: String?, unit: String) -> Text {
    guard let value else { return Text("Sin datos") }
    guard !unit.isEmpty else { return Text(verbatim: value) }
    return Text("\(value) \(Text(LocalizedStringKey(unit)))")
}

/// Tesela de métrica para cuadrículas del dashboard.
public struct HalsynMetricTile: View {
    private let title: String
    private let systemImage: String
    private let value: String?
    private let unit: String
    private let status: String?

    /// - Parameter status: texto que explica la ausencia de valor (sin datos,
    ///   sin permiso, no soportado) o un matiz del valor.
    public init(title: String, systemImage: String, value: String?, unit: String, status: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.unit = unit
        self.status = status
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.halsynAccent)
                .accessibilityHidden(true)
            HalsynMetric(title: title, value: value, unit: unit)
            if let status, !status.isEmpty {
                Text(LocalizedStringKey(status))
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .lineLimit(2)
            }
        }
        .padding(HalsynSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous)
                .fill(Color.halsynSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous)
                .strokeBorder(Color.halsynHairline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Indicador de estado: siempre icono + texto, nunca solo color.
public struct HalsynStatusIndicator: View {
    public enum Level: Sendable {
        case positive, neutral, caution, alert

        var systemImage: String {
            switch self {
            case .positive: "checkmark.circle.fill"
            case .neutral: "circle.dotted"
            case .caution: "exclamationmark.triangle.fill"
            case .alert: "exclamationmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .positive: .halsynPositive
            case .neutral: .halsynSecondaryText
            case .caution: .halsynCaution
            case .alert: .halsynAlert
            }
        }
    }

    private let level: Level
    private let text: String

    public init(_ level: Level, text: String) {
        self.level = level
        self.text = text
    }

    public var body: some View {
        Label {
            Text(LocalizedStringKey(text))
        } icon: {
            Image(systemName: level.systemImage)
        }
        .font(.halsynCaption)
        .foregroundStyle(level.color)
    }
}

/// Barra de progreso redondeada.
public struct HalsynProgressBar: View {
    private let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double) {
        self.progress = min(max(progress, 0), 1)
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.halsynAccentSoft.opacity(0.45))
                Capsule()
                    .fill(HalsynGradients.brand)
                    .frame(width: max(proxy.size.height, proxy.size.width * progress))
                    .opacity(progress > 0 ? 1 : 0)
            }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: progress)
        .accessibilityElement()
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// Anillo de puntuación. El extremo del arco termina en un círculo, eco de la
/// cabeza del símbolo Å-persona.
public struct HalsynScoreRing: View {
    private let score: Int?
    private let caption: String?
    private let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    /// - Parameter score: 0...100, o `nil` si no hay datos suficientes.
    public init(score: Int?, caption: String? = nil, lineWidth: CGFloat = 14) {
        self.score = score
        self.caption = caption
        self.lineWidth = lineWidth
    }

    private var progress: Double { Double(score ?? 0) / 100 }
    private var isLow: Bool { (score ?? 100) < 34 }

    public var body: some View {
        ZStack {
            // El trazo se mete medio grosor hacia dentro: así el arco, la pista y la
            // bola del extremo comparten exactamente el mismo radio (centro del trazo).
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.halsynAccentSoft.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: animatedProgress)
                // Puntuación baja: anillo cálido (naranja → coral) en lugar del turquesa.
                .stroke(isLow ? AnyShapeStyle(HalsynGradients.ember) : AnyShapeStyle(HalsynGradients.ring), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            GeometryReader { proxy in
                let radius = (min(proxy.size.width, proxy.size.height) - lineWidth) / 2
                let angle = Angle.degrees(animatedProgress * 360 - 90)
                Circle()
                    .fill(isLow ? Color(HalsynPalette.emberDark) : Color(HalsynPalette.mint))
                    .overlay(Circle().strokeBorder(Color.halsynSurface, lineWidth: 2))
                    .frame(width: lineWidth * 1.1, height: lineWidth * 1.1)
                    .position(
                        x: proxy.size.width / 2 + radius * CGFloat(cos(angle.radians)),
                        y: proxy.size.height / 2 + radius * CGFloat(sin(angle.radians))
                    )
                    .opacity(score == nil || animatedProgress == 0 ? 0 : 1)
            }
            VStack(spacing: 2) {
                Text(verbatim: score.map(String.init) ?? "—")
                    .font(.system(size: 56, weight: .light, design: .default).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.halsynPrimaryText)
                if let caption {
                    Text(LocalizedStringKey(caption))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(lineWidth * 1.5)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { update(animated: !reduceMotion) }
        .onChange(of: score) { _, _ in update(animated: !reduceMotion) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Puntuación"))
        .accessibilityValue(score.map { Text(verbatim: "\($0) / 100") } ?? Text("Sin datos suficientes"))
    }

    private func update(animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { animatedProgress = progress }
        } else {
            animatedProgress = progress
        }
    }
}
#endif
