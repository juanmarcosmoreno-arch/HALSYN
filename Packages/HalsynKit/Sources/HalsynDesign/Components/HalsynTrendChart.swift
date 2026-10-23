#if canImport(SwiftUI) && canImport(Charts)
import Charts
import HalsynCore
import SwiftUI
#if canImport(Accessibility)
import Accessibility
#endif

/// Gráfico de tendencia diaria de HÅLSYN.
///
/// Lo que lo distingue:
/// - **Lectura en cabecera**: el valor (último o el que tocas) va arriba, grande,
///   con su fecha y su comparación; nunca tapa los datos con un globo.
/// - **Tu rango habitual**: banda suave con tu media ± 1 desviación de las
///   semanas anteriores; los días fuera de la banda se marcan con un punto.
/// - **Huecos honestos**: si falta un día la línea se corta; no se inventa la unión.
/// - **Objetivo** como línea fina y sólida con su etiqueta; las barras que no
///   lo alcanzan se atenúan (énfasis, no colores de alarma).
/// - Exploración con el dedo con respuesta háptica, curva monótona (sin picos
///   que no existen) y descripción para VoiceOver y Audiogramas.
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
    private let usualRange: ClosedRange<Double>?
    private let target: Double?
    private let unit: String
    private let format: (Double) -> String
    private let showsReadout: Bool

    @State private var selectedDate: Date?

    /// - Parameters:
    ///   - usualRange: rango habitual personal (p. ej. media ± 1 desviación de 28 días).
    ///   - target: objetivo diario (línea de referencia).
    ///   - unit: unidad que acompaña al valor en la cabecera.
    ///   - format: formato del valor (por defecto, entero en el idioma del usuario).
    ///   - showsReadout: cabecera con el valor seleccionado o el último.
    public init(
        values: [DailyValue],
        title: String,
        style: Style = .line,
        showsAverage: Bool = true,
        yDomain: ClosedRange<Double>? = nil,
        usualRange: ClosedRange<Double>? = nil,
        target: Double? = nil,
        unit: String = "",
        format: @escaping (Double) -> String = { HalsynFormat.integer($0) },
        showsReadout: Bool = true
    ) {
        self.values = values.sorted { $0.day < $1.day }
        self.title = title
        self.style = style
        self.showsAverage = showsAverage
        self.yDomain = yDomain
        self.usualRange = usualRange
        self.target = target
        self.unit = unit
        self.format = format
        self.showsReadout = showsReadout
    }

    // MARK: Datos derivados

    private var calendar: Calendar { .current }

    private var average: Double? {
        guard !values.isEmpty else { return nil }
        return values.map(\.value).reduce(0, +) / Double(values.count)
    }

    /// Tramos de días consecutivos: la línea no une días con huecos.
    private var segments: [[DailyValue]] {
        var result: [[DailyValue]] = []
        for value in values {
            if let last = result.last?.last,
               let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.day), to: calendar.startOfDay(for: value.day)).day,
               gap <= 1 {
                result[result.count - 1].append(value)
            } else {
                result.append([value])
            }
        }
        return result
    }

    private var resolvedDomain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        var numbers = values.map(\.value)
        if let usualRange { numbers += [usualRange.lowerBound, usualRange.upperBound] }
        if let target { numbers.append(target) }
        guard let low = numbers.min(), let high = numbers.max() else { return 0...1 }
        if style == .bar { return 0...(max(high, 0.001) * 1.12) }
        let padding = max((high - low) * 0.18, abs(high) * 0.02, 0.5)
        return (low - padding)...(high + padding)
    }

    private var xDomain: ClosedRange<Date> {
        let first = calendar.startOfDay(for: values.first?.day ?? .now)
        let last = calendar.startOfDay(for: values.last?.day ?? .now)
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return first...end
    }

    private var xAxisFormat: Date.FormatStyle {
        switch values.count {
        case ...10: .dateTime.weekday(.narrow)
        case ...62: .dateTime.day().month(.defaultDigits)
        default: .dateTime.month(.abbreviated)
        }
    }

    private var selectedDay: Date? {
        guard let selectedDate else { return nil }
        let day = calendar.startOfDay(for: selectedDate)
        return xDomain.contains(day) ? day : nil
    }

    private var selectedValue: DailyValue? {
        guard let selectedDay else { return nil }
        return values.first { calendar.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private func isOutsideUsual(_ value: Double) -> Bool {
        guard let usualRange else { return false }
        return !usualRange.contains(value)
    }

    // MARK: Vista

    public var body: some View {
        if values.isEmpty {
            HalsynEmptyState(systemImage: "chart.xyaxis.line", title: "Sin datos", message: "Aún no hay suficientes registros para este periodo.")
        } else {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                if showsReadout {
                    readout
                }
                chart
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: resolvedDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: values.count <= 10 ? values.count : 5)) { _ in
                            AxisValueLabel(format: xAxisFormat, centered: style == .bar)
                                .foregroundStyle(Color.halsynSecondaryText)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.halsynHairline)
                            AxisValueLabel()
                                .foregroundStyle(Color.halsynSecondaryText)
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .sensoryFeedback(.selection, trigger: selectedDay)
                    .chartAccessibility(values: values, title: title, unit: unit, format: format)
                if usualRange != nil || target != nil {
                    legend
                }
            }
        }
    }

    // MARK: Cabecera

    private var readout: some View {
        let shown = selectedValue ?? (selectedDay == nil ? values.last : nil)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map { format($0.value) } ?? "—")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.halsynPrimaryText)
                        .contentTransition(.numericText())
                    if shown != nil, !unit.isEmpty {
                        Text(LocalizedStringKey(unit))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
                Group {
                    if let selectedDay {
                        if shown == nil {
                            Text("Sin dato este día")
                        } else {
                            Text(selectedDay, format: .dateTime.weekday(.wide).day().month(.wide))
                        }
                    } else if let last = values.last {
                        Text(last.day, format: .dateTime.weekday(.wide).day().month(.wide))
                    }
                }
                .font(.caption)
                .foregroundStyle(.halsynSecondaryText)
            }
            Spacer(minLength: HalsynSpacing.s)
            if let shown {
                comparison(for: shown.value)
            }
        }
        .animation(.snappy(duration: 0.2), value: shown?.day)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func comparison(for value: Double) -> some View {
        if let usualRange {
            let (key, icon): (LocalizedStringKey, String) = value > usualRange.upperBound
                ? ("Por encima de lo habitual", "arrow.up.right")
                : (value < usualRange.lowerBound ? ("Por debajo de lo habitual", "arrow.down.right") : ("En tu rango habitual", "checkmark"))
            chip(Label(key, systemImage: icon))
        } else if let target {
            chip(Label(value >= target ? LocalizedStringKey("Objetivo cumplido") : LocalizedStringKey("Por debajo del objetivo"), systemImage: value >= target ? "checkmark" : "minus"))
        } else if showsAverage, let average {
            chip(Text("Media \(format(average))"))
        }
    }

    private func chip<Content: View>(_ content: Content) -> some View {
        content
            .font(.caption2.weight(.medium))
            .foregroundStyle(.halsynSecondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.halsynHairline.opacity(0.6)))
    }

    private var legend: some View {
        HStack(spacing: HalsynSpacing.m) {
            if usualRange != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.halsynChart.opacity(0.16)).frame(width: 14, height: 10)
                    Text("Tu rango habitual")
                }
            }
            if target != nil {
                HStack(spacing: 6) {
                    Capsule().fill(Color.halsynPrimaryText.opacity(0.55)).frame(width: 14, height: 1.5)
                    Text("Objetivo")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.halsynSecondaryText)
        .accessibilityHidden(true)
    }

    // MARK: Gráfico

    private var chart: some View {
        Chart {
            if let usualRange {
                RectangleMark(
                    xStart: .value("Inicio", xDomain.lowerBound),
                    xEnd: .value("Fin", xDomain.upperBound),
                    yStart: .value("Habitual mín.", usualRange.lowerBound),
                    yEnd: .value("Habitual máx.", usualRange.upperBound)
                )
                .foregroundStyle(Color.halsynChart.opacity(0.10))
            } else if showsAverage, target == nil, let average {
                RuleMark(y: .value("Media", average))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.halsynSecondaryText.opacity(0.35))
            }

            if let target {
                RuleMark(y: .value("Objetivo", target))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .foregroundStyle(Color.halsynPrimaryText.opacity(0.45))
            }

            if style == .line {
                lineMarks
            } else {
                barMarks
            }

            if let selectedDay {
                RuleMark(x: .value("Día", selectedDay, unit: .day))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.halsynSecondaryText.opacity(0.5))
            }
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        let lowest = resolvedDomain.lowerBound
        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
            ForEach(segment) { item in
                AreaMark(
                    x: .value("Día", item.day, unit: .day),
                    yStart: .value(title, lowest),
                    yEnd: .value(title, item.value),
                    series: .value("Tramo", index)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(areaWash)
            }
        }
        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
            ForEach(segment) { item in
                LineMark(
                    x: .value("Día", item.day, unit: .day),
                    y: .value(title, item.value),
                    series: .value("Tramo", index)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.halsynChart)
            }
        }
        // Puntos aislados (sin vecinos), fuera de lo habitual, el último y el seleccionado.
        ForEach(values.filter { item in isolated(item) || isOutsideUsual(item.value) || item.day == values.last?.day || item.day == selectedValue?.day }) { item in
            PointMark(x: .value("Día", item.day, unit: .day), y: .value(title, item.value))
                .symbolSize(item.day == selectedValue?.day ? 150 : 90)
                .foregroundStyle(Color.halsynSurface)
            PointMark(x: .value("Día", item.day, unit: .day), y: .value(title, item.value))
                .symbolSize(item.day == selectedValue?.day ? 70 : 36)
                // Fuera de tu rango habitual: acento cálido para que salte a la vista.
                .foregroundStyle(isOutsideUsual(item.value) ? Color.halsynHighlight : Color.halsynChart)
        }
    }

    @ChartContentBuilder
    private var barMarks: some ChartContent {
        ForEach(values) { item in
            BarMark(
                x: .value("Día", item.day, unit: .day),
                y: .value(title, item.value),
                width: barWidth
            )
            .cornerRadius(4)
            .foregroundStyle(Color.halsynChart.opacity(barOpacity(item)))
        }
    }

    private var barWidth: MarkDimension {
        switch values.count {
        case ...10: .fixed(20)
        case ...31: .ratio(0.62)
        default: .ratio(0.72)
        }
    }

    private func barOpacity(_ item: DailyValue) -> Double {
        if let selectedValue {
            return item.day == selectedValue.day ? 1 : 0.3
        }
        if let target, item.value < target { return 0.42 }
        return 1
    }

    private func isolated(_ item: DailyValue) -> Bool {
        segments.contains { $0.count == 1 && $0.first?.day == item.day }
    }

    private var areaWash: LinearGradient {
        LinearGradient(colors: [Color.halsynChart.opacity(0.16), Color.halsynChart.opacity(0.01)], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Accesibilidad (VoiceOver y Audiogramas)

private struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let values: [DailyValue]
    let title: String
    let unit: String
    let format: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = values.map { $0.day.formatted(.dateTime.day().month(.abbreviated)) }
        let numbers = values.map(\.value)
        let low = numbers.min() ?? 0
        let high = numbers.max() ?? 1
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Día"), categoryOrder: dates)
        let yAxis = AXNumericDataAxisDescriptor(title: title, range: low...max(high, low + 1), gridlinePositions: []) { value in
            "\(format(value)) \(unit)"
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: true, dataPoints: zip(dates, numbers).map { AXDataPoint(x: $0, y: $1) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

extension View {
    func chartAccessibility(values: [DailyValue], title: String, unit: String, format: @escaping (Double) -> String) -> some View {
        accessibilityChartDescriptor(TrendChartDescriptor(values: values, title: title, unit: unit, format: format))
    }
}
#endif
