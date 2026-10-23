#if canImport(SwiftUI) && canImport(Charts)
import Charts
import HalsynCore
import SwiftUI

/// Antes y después: los valores diarios de 8 semanas, tenues, con la media de
/// cada mitad como un tramo grueso. Se ve el cambio y también el ruido del día a día.
public struct HalsynPeriodComparisonChart: View {
    private let values: [DailyValue]
    private let splitDay: Date
    private let previousMean: Double
    private let recentMean: Double
    private let format: (Double) -> String

    public init(values: [DailyValue], splitDay: Date, previousMean: Double, recentMean: Double, format: @escaping (Double) -> String = { HalsynFormat.integer($0) }) {
        self.values = values.sorted { $0.day < $1.day }
        self.splitDay = splitDay
        self.previousMean = previousMean
        self.recentMean = recentMean
        self.format = format
    }

    private var domain: ClosedRange<Double> {
        let numbers = values.map(\.value) + [previousMean, recentMean]
        let low = numbers.min() ?? 0, high = numbers.max() ?? 1
        let padding = max((high - low) * 0.15, abs(high) * 0.02, 0.5)
        return (low - padding)...(high + padding)
    }

    public var body: some View {
        let first = values.first?.day ?? splitDay
        let last = Calendar.current.date(byAdding: .day, value: 1, to: values.last?.day ?? splitDay) ?? splitDay
        Chart {
            ForEach(values) { value in
                PointMark(x: .value("Día", value.day, unit: .day), y: .value("Valor", value.value))
                    .symbolSize(14)
                    .foregroundStyle(Color.halsynSecondaryText.opacity(0.35))
            }
            RuleMark(xStart: .value("Inicio", first), xEnd: .value("Cambio", splitDay), y: .value("Media anterior", previousMean))
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                .foregroundStyle(Color.halsynSecondaryText.opacity(0.7))
                .annotation(position: .top, alignment: .leading, spacing: 4) {
                    Text(verbatim: format(previousMean))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.halsynSecondaryText)
                }
            RuleMark(xStart: .value("Cambio", splitDay), xEnd: .value("Fin", last), y: .value("Media reciente", recentMean))
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                .foregroundStyle(Color.halsynChart)
                .annotation(position: .top, alignment: .trailing, spacing: 4) {
                    Text(verbatim: format(recentMean))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.halsynPrimaryText)
                }
        }
        .chartXScale(domain: first...last)
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [first, splitDay]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.halsynHairline)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Color.halsynSecondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Media anterior \(format(previousMean)), media reciente \(format(recentMean))"))
    }
}

/// Dos grupos sobre un mismo eje (gráfico de pesas): sin barras desde cero que
/// exageren o escondan la diferencia, y con el tamaño de cada grupo.
public struct HalsynGroupComparison: View {
    private let lowLabel: String
    private let highLabel: String
    private let lowValue: Double
    private let highValue: Double
    private let format: (Double) -> String

    public init(lowLabel: String, highLabel: String, lowValue: Double, highValue: Double, format: @escaping (Double) -> String) {
        self.lowLabel = lowLabel
        self.highLabel = highLabel
        self.lowValue = lowValue
        self.highValue = highValue
        self.format = format
    }

    public var body: some View {
        let low = min(lowValue, highValue), high = max(lowValue, highValue)
        let span = max(high - low, abs(high) * 0.05, 0.001)
        let lower = low - span * 0.6, upper = high + span * 0.6
        GeometryReader { proxy in
            let width = proxy.size.width
            let x: (Double) -> CGFloat = { CGFloat(($0 - lower) / (upper - lower)) * width }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.halsynHairline).frame(width: width, height: 2).offset(y: 29)
                Capsule().fill(Color.halsynChart.opacity(0.35))
                    .frame(width: max(2, abs(x(highValue) - x(lowValue))), height: 4)
                    .offset(x: min(x(lowValue), x(highValue)), y: 28)
                marker(value: lowValue, label: lowLabel, emphasized: false, x: x(lowValue), width: width)
                marker(value: highValue, label: highLabel, emphasized: true, x: x(highValue), width: width)
            }
        }
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(highLabel): \(format(highValue)). \(lowLabel): \(format(lowValue))."))
    }

    private func marker(value: Double, label: String, emphasized: Bool, x: CGFloat, width: CGFloat) -> some View {
        let alignment: HorizontalAlignment = x < width * 0.25 ? .leading : (x > width * 0.75 ? .trailing : .center)
        let labelWidth: CGFloat = 120
        let offset = alignment == .leading ? x - 6 : (alignment == .trailing ? x - labelWidth + 6 : x - labelWidth / 2)
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(emphasized ? Color.halsynChart : Color.halsynSecondaryText.opacity(0.7))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.halsynSurface, lineWidth: 2))
                .offset(x: x - 6, y: 24)
            VStack(alignment: alignment, spacing: 0) {
                Text(verbatim: format(value))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(emphasized ? Color.halsynPrimaryText : Color.halsynSecondaryText)
                Spacer().frame(height: 22)
                Text(verbatim: label)
                    .font(.caption2)
                    .foregroundStyle(Color.halsynSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: labelWidth, alignment: Alignment(horizontal: alignment, vertical: .top))
            .offset(x: min(max(offset, 0), width - labelWidth), y: 0)
        }
    }
}

/// Semana tipo: siete columnas con la media de cada día; el día más alto
/// resaltado, el resto atenuados (énfasis, no una escala de colores).
public struct HalsynWeekdayChart: View {
    private let means: [Int: Double]
    private let highlight: Int
    private let format: (Double) -> String

    /// - Parameter means: media por `Calendar.weekday` (1 = domingo).
    public init(means: [Int: Double], highlight: Int, format: @escaping (Double) -> String = { HalsynFormat.integer($0) }) {
        self.means = means
        self.highlight = highlight
        self.format = format
    }

    /// Días en el orden local de la semana (lunes primero en España, domingo en EE. UU.).
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    public var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let maximum = max(means.values.max() ?? 1, 0.001)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let value = means[weekday] ?? 0
                VStack(spacing: 4) {
                    if weekday == highlight {
                        Text(verbatim: format(value))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.halsynPrimaryText)
                            .fixedSize()
                    }
                    UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                        .fill(Color.halsynChart.opacity(weekday == highlight ? 1 : 0.35))
                        .frame(maxWidth: 24)
                        .frame(height: max(4, 90 * value / maximum))
                    Text(verbatim: symbols[weekday - 1])
                        .font(.caption2)
                        .foregroundStyle(weekday == highlight ? Color.halsynPrimaryText : Color.halsynSecondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(Calendar.current.weekdaySymbols[weekday - 1]): \(format(value))"))
            }
        }
        .frame(height: 130, alignment: .bottom)
    }
}
#endif
