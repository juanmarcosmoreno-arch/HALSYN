#if canImport(SwiftUI)
import HalsynCore
import SwiftUI

/// Dónde cae un valor dentro de la tabla publicada de su grupo de edad y sexo.
///
/// Escala horizontal con los valores de la tabla (no de percentiles):
/// - banda clara: del percentil más bajo al más alto publicados (p. ej. P5–P95);
/// - banda media: P25–P75, la mitad central del grupo;
/// - raya: mediana (P50);
/// - punto: tu valor. Fuera de la tabla se queda en el borde con una flecha,
///   sin inventar un percentil.
public struct HalsynReferenceStrip: View {
    private let position: ReferencePosition
    private let unit: String
    private let format: (Double) -> String

    public init(position: ReferencePosition, unit: String, format: @escaping (Double) -> String) {
        self.position = position
        self.unit = unit
        self.format = format
    }

    private var points: [(key: Double, value: Double)] {
        position.row.percentiles.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Dominio con un pequeño margen para que el punto y las etiquetas respiren.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value) + [position.value]
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.06, 0.5)
        return (low - pad)...(high + pad)
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return width / 2 }
        return CGFloat((value - domain.lowerBound) / span) * width
    }

    private func value(at percentile: Double) -> Double? {
        position.row.percentiles[percentile]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let barY: CGFloat = 30
                ZStack(alignment: .topLeading) {
                    if let first = points.first, let last = points.last {
                        Capsule()
                            .fill(Color.halsynChart.opacity(0.12))
                            .frame(width: max(x(last.value, width: width) - x(first.value, width: width), 2), height: 12)
                            .offset(x: x(first.value, width: width), y: barY - 6)
                    }
                    if let q1 = value(at: 25), let q3 = value(at: 75) {
                        Capsule()
                            .fill(Color.halsynChart.opacity(0.30))
                            .frame(width: max(x(q3, width: width) - x(q1, width: width), 2), height: 12)
                            .offset(x: x(q1, width: width), y: barY - 6)
                    }
                    if let median = position.median {
                        Rectangle()
                            .fill(Color.halsynPrimaryText.opacity(0.55))
                            .frame(width: 1.5, height: 20)
                            .offset(x: x(median, width: width) - 0.75, y: barY - 10)
                    }
                    marker(width: width, barY: barY)
                }
            }
            .frame(height: 44)

            axis
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private func marker(width: CGFloat, barY: CGFloat) -> some View {
        let markerX = x(position.value, width: width)
        let label = "\(format(position.value)) \(unit)".trimmingCharacters(in: .whitespaces)
        // Etiqueta encima del punto, sin salirse por los bordes.
        Text(verbatim: label)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.halsynPrimaryText)
            .fixedSize()
            .frame(width: 90, alignment: markerX < 45 ? .leading : (markerX > width - 45 ? .trailing : .center))
            .offset(x: min(max(markerX - 45, 0), width - 90), y: 0)
        Circle()
            .fill(Color.halsynAccent)
            .overlay(Circle().strokeBorder(Color.halsynSurface, lineWidth: 2))
            .frame(width: 16, height: 16)
            .offset(x: markerX - 8, y: barY - 8)
        switch position.bound {
        case .above:
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 8))
                .foregroundStyle(.halsynAccent)
                .offset(x: markerX + 9, y: barY - 5)
        case .below:
            Image(systemName: "arrowtriangle.left.fill")
                .font(.system(size: 8))
                .foregroundStyle(.halsynAccent)
                .offset(x: markerX - 17, y: barY - 5)
        case .within:
            EmptyView()
        }
    }

    /// Valores de la tabla bajo la escala: extremo bajo, mediana y extremo alto.
    private var axis: some View {
        HStack {
            if let first = points.first { axisLabel(first.key, first.value, alignment: .leading) }
            Spacer()
            if let median = position.median { axisLabel(50, median, alignment: .center) }
            Spacer()
            if let last = points.last { axisLabel(last.key, last.value, alignment: .trailing) }
        }
    }

    private func axisLabel(_ percentile: Double, _ value: Double, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(verbatim: format(value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.halsynPrimaryText)
            Text(verbatim: "P\(Self.percentileText(percentile))")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Capsule().fill(Color.halsynChart.opacity(0.30)).frame(width: 14, height: 8)
                Text("Mitad central del grupo")
            }
            HStack(spacing: 4) {
                Rectangle().fill(Color.halsynPrimaryText.opacity(0.55)).frame(width: 1.5, height: 10)
                Text("Mediana")
            }
            HStack(spacing: 4) {
                Circle().fill(Color.halsynAccent).frame(width: 8, height: 8)
                Text("Tú")
            }
        }
        .font(.caption2)
        .foregroundStyle(.halsynSecondaryText)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let value = "\(format(position.value)) \(unit)"
        switch position.bound {
        case .within(let percentile):
            return String(localized: "Tu valor, \(value), está cerca del percentil \(Self.percentileText(percentile)) de tu grupo.", bundle: .main)
        case .below(let percentile):
            return String(localized: "Tu valor, \(value), está por debajo del percentil \(Self.percentileText(percentile)) de la tabla.", bundle: .main)
        case .above(let percentile):
            return String(localized: "Tu valor, \(value), está por encima del percentil \(Self.percentileText(percentile)) de la tabla.", bundle: .main)
        }
    }

    /// "5", "2,5", "97,5": sin decimales si es entero.
    public static func percentileText(_ percentile: Double) -> String {
        percentile.rounded() == percentile
            ? String(Int(percentile))
            : percentile.formatted(.number.precision(.fractionLength(1)))
    }
}
#endif
