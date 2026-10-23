#if canImport(SwiftUI) && canImport(Charts)
import Charts
import HalsynCore
import SwiftUI

/// Gráfico de tendencia diaria (Swift Charts).
public struct HalsynTrendChart: View {
    public enum Style: Sendable {
        case line
        case bar
    }

    private let values: [DailyValue]
    private let title: String
    private let style: Style
    private let showsAverage: Bool
    private let yDomain: ClosedRange<Double>?

    public init(values: [DailyValue], title: String, style: Style = .line, showsAverage: Bool = true, yDomain: ClosedRange<Double>? = nil) {
        self.values = values
        self.title = title
        self.style = style
        self.showsAverage = showsAverage
        self.yDomain = yDomain
    }

    private var average: Double? {
        guard !values.isEmpty else { return nil }
        return values.map(\.value).reduce(0, +) / Double(values.count)
    }

    private var resolvedDomain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let numbers = values.map(\.value)
        guard let low = numbers.min(), let high = numbers.max() else { return 0...1 }
        if style == .bar { return 0...(high * 1.1) }
        let padding = max((high - low) * 0.2, abs(high) * 0.02, 0.5)
        return (low - padding)...(high + padding)
    }

    /// Etiquetas del eje X adaptadas a la longitud del periodo.
    private var xAxisFormat: Date.FormatStyle {
        switch values.count {
        case ...10: .dateTime.weekday(.narrow)
        case ...62: .dateTime.day().month(.defaultDigits)
        default: .dateTime.month(.abbreviated)
        }
    }

    public var body: some View {
        if values.isEmpty {
            HalsynEmptyState(systemImage: "chart.xyaxis.line", title: "Sin datos", message: "Aún no hay suficientes registros para este periodo.")
        } else {
            chart
                .chartYScale(domain: resolvedDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: values.count <= 10 ? values.count : 5)) { _ in
                        AxisValueLabel(format: xAxisFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(Color.halsynHairline)
                        AxisValueLabel()
                    }
                }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(values) { item in
                switch style {
                case .line:
                    AreaMark(
                        x: .value("Día", item.day, unit: .day),
                        yStart: .value(title, resolvedDomain.lowerBound),
                        yEnd: .value(title, item.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(
                        colors: [Color.halsynAccent.opacity(0.25), Color.halsynAccent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    LineMark(x: .value("Día", item.day, unit: .day), y: .value(title, item.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(Color.halsynAccent)
                case .bar:
                    BarMark(x: .value("Día", item.day, unit: .day), y: .value(title, item.value), width: .ratio(0.45))
                        .cornerRadius(4)
                        .foregroundStyle(HalsynGradients.brand)
                }
            }
            if showsAverage, let average {
                RuleMark(y: .value("Media", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.halsynSecondaryText.opacity(0.6))
            }
        }
    }
}
#endif
