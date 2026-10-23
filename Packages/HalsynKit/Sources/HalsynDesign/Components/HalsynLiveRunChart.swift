#if canImport(SwiftUI) && canImport(Charts)
import Charts
import HalsynCore
import SwiftUI

/// Gráfico en vivo de la carrera: se dibuja a medida que corres.
/// Ritmo (más rápido = más arriba) o frecuencia cardíaca; tocar cambia de uno a otro.
public struct HalsynLiveRunChart: View {
    public enum Metric: Sendable {
        case pace
        case heartRate
    }

    private let paceSamples: [LiveSample]
    private let heartRateSamples: [LiveSample]
    private let averagePace: Pace?
    private let currentPace: Pace?
    private let heartRate: Double?
    private let paceTarget: PaceRange?
    private let unit: UnitSystem
    @State private var metric: Metric

    public init(
        paceSamples: [LiveSample],
        heartRateSamples: [LiveSample],
        averagePace: Pace?,
        currentPace: Pace?,
        heartRate: Double?,
        paceTarget: PaceRange? = nil,
        unit: UnitSystem = .metric,
        initialMetric: Metric = .pace
    ) {
        // Fuera ritmos de paseo (> 15 min/km): aplanarían la escala.
        self.paceSamples = paceSamples.filter { $0.value <= 900 }.smoothed(window: 3).downsampled(maxPoints: 240)
        self.heartRateSamples = heartRateSamples.downsampled(maxPoints: 240)
        self.averagePace = averagePace
        self.currentPace = currentPace
        self.heartRate = heartRate
        self.paceTarget = paceTarget
        self.unit = unit
        _metric = State(initialValue: initialMetric)
    }

    private var tint: Color {
        metric == .pace ? Color(HalsynPalette.darkSecondary) : Color(HalsynPalette.alertDark)
    }

    /// En ritmo se dibuja el valor negado para que lo rápido quede arriba.
    private var points: [LiveSample] {
        switch metric {
        case .pace: paceSamples.map { LiveSample(elapsed: $0.elapsed, value: -$0.value * unit.metersPerDistanceUnit / 1000) }
        case .heartRate: heartRateSamples
        }
    }

    private var reference: Double? {
        switch metric {
        case .pace: averagePace.map { -$0.seconds(per: unit) }
        case .heartRate: heartRateSamples.isEmpty ? nil : heartRateSamples.map(\.value).reduce(0, +) / Double(heartRateSamples.count)
        }
    }

    private var domain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let reference { values.append(reference) }
        if metric == .pace, let paceTarget {
            values += [-paceTarget.fastest * unit.metersPerDistanceUnit / 1000, -paceTarget.slowest * unit.metersPerDistanceUnit / 1000]
        }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let minimumSpan: Double = metric == .pace ? 30 : 10
        let span = max(high - low, minimumSpan)
        let middle = (low + high) / 2
        return (middle - span * 0.65)...(middle + span * 0.65)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if points.count < 2 {
                Text(metric == .pace ? "El gráfico aparece al empezar a moverte" : "Esperando la frecuencia cardíaca")
                    .font(.caption2)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { metric = metric == .pace ? .heartRate : .pace }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Toca para cambiar entre ritmo y frecuencia cardíaca"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric == .pace ? "RITMO" : "PULS")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(tint)
            Spacer(minLength: 2)
            Text(verbatim: metric == .pace ? (currentPace?.formatted(in: unit) ?? "--") : (heartRate.map { HalsynFormat.integer($0) } ?? "--"))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
            Text(LocalizedStringKey(metric == .pace ? unit.paceUnitSymbol : "lpm"))
                .font(.caption2)
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
        }
    }

    private var chart: some View {
        let data = points
        let last = data.last
        return Chart {
            if metric == .pace, let paceTarget {
                RectangleMark(
                    yStart: .value("Objetivo rápido", -paceTarget.fastest * unit.metersPerDistanceUnit / 1000),
                    yEnd: .value("Objetivo lento", -paceTarget.slowest * unit.metersPerDistanceUnit / 1000)
                )
                .foregroundStyle(tint.opacity(0.14))
            }
            if let reference {
                RuleMark(y: .value("Media", reference))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .annotation(position: .top, alignment: .leading, spacing: 1) {
                        Text("MEDIA")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
            }
            ForEach(data, id: \.elapsed) { sample in
                AreaMark(x: .value("Tiempo", sample.elapsed), yStart: .value("Base", domain.lowerBound), yEnd: .value("Valor", sample.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            ForEach(data, id: \.elapsed) { sample in
                LineMark(x: .value("Tiempo", sample.elapsed), y: .value("Valor", sample.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
            }
            if let last {
                PointMark(x: .value("Tiempo", last.elapsed), y: .value("Valor", last.value))
                    .symbolSize(90)
                    .foregroundStyle(Color.black)
                PointMark(x: .value("Tiempo", last.elapsed), y: .value("Valor", last.value))
                    .symbolSize(40)
                    .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...max(last?.elapsed ?? 60, 60))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(verbatim: "\(Int(seconds / 60))′")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: data.count)
    }
}
#endif

#if canImport(SwiftUI)
/// Indicador de zona cardíaca: cinco segmentos de intensidad creciente; el
/// actual, lleno y más alto. Se lee de un vistazo con el brazo en movimiento.
public struct HalsynZoneGauge: View {
    private let zone: Int

    /// - Parameter zone: 0 (por debajo de Z1) … 5.
    public init(zone: Int) {
        self.zone = zone
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                Capsule()
                    .fill(Color(HalsynPalette.alertDark).opacity(index == zone ? 1 : 0.18 + 0.08 * Double(index)))
                    .frame(height: index == zone ? 7 : 4)
            }
        }
        .frame(height: 8)
        .animation(.snappy, value: zone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: zone == 0 ? "<Z1" : "Z\(zone)"))
    }
}
#endif
