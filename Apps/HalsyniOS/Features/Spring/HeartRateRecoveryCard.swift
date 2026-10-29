import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// "Recuperación del pulso": cuánto baja la FC en el primer minuto y a los 2
/// minutos después de terminar, con la curva de la última medición y la
/// evolución. Son las mediciones que guardaste desde el reloj; la «Recuperación
/// cardíaca» que estima el Apple Watch se muestra aparte (se calcula distinto).
struct HeartRateRecoveryCard: View {
    @Environment(AppModel.self) private var model
    @State private var history = RecoveryHistoryStore.shared
    @State private var demoReadings: [RecoveryReading] = []
    @State private var healthReadings: [RecoveryReading] = []
    @State private var loaded = false

    /// Mediciones de HÅLSYN (en demo, las de ejemplo).
    private var readings: [RecoveryReading] {
        model.isDemo ? demoReadings : history.results.compactMap { RecoveryReading($0) }
    }

    /// Curva de la última medición guardada (no hay en demo).
    private var lastCurve: HeartRateRecoveryResult? {
        model.isDemo ? nil : history.results.last
    }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Recuperación del pulso", eyebrow: HalsynLexicon.puls.rawValue)
                if !loaded {
                    HalsynLoadingState()
                } else if let last = readings.last {
                    lastMeasurement(last)
                    trendSection
                } else {
                    Text("Al terminar una carrera en el reloj, elige «Guardar y medir recuperación» y camina despacio: el reloj mide cuánto baja tu pulso en 1 y 2 minutos y te pregunta si guardarlo.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                }
                appleSection
                explanation
            }
        }
        .task(id: model.reloadKey) {
            let fromHealth = await model.provider.heartRateRecoveries(days: 180)
            if model.isDemo {
                demoReadings = fromHealth
                healthReadings = []
            } else {
                demoReadings = []
                healthReadings = fromHealth
            }
            loaded = true
        }
    }

    @ViewBuilder
    private func lastMeasurement(_ last: RecoveryReading) -> some View {
        HStack(alignment: .top) {
            HalsynMetric(title: "1 min", value: HalsynFormat.drop(last.oneMinute), unit: "lpm")
            Spacer()
            HalsynMetric(title: "2 min", value: last.twoMinutes.map { HalsynFormat.drop($0) }, unit: "lpm")
            Spacer()
            HalsynMetric(title: "Al terminar", value: last.endHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm", alignment: .trailing)
        }
        Text(last.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
        if let curve = lastCurve, curve.samples.count > 2 {
            RecoveryCurveChart(result: curve)
                .frame(height: 120)
        }
        if last.origin.isDemo {
            DataOriginFootnote(origin: last.origin)
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        if readings.count > 1 {
            RecoveryTrendChart(readings: readings)
                .frame(height: 130)
        }
        if let trend = RecoveryTrend.make(readings) {
            Text(trendText(trend))
                .font(.halsynCaption)
                .foregroundStyle(.halsynPrimaryText)
        } else {
            Text("Hacen falta 10 mediciones que terminen con un pulso parecido para ver si tu recuperación cambia.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private func trendText(_ trend: RecoveryTrend) -> LocalizedStringKey {
        let difference = HalsynFormat.integer(abs(trend.change))
        let count = trend.count
        guard trend.isMeaningful else {
            return "Tus últimas \(count) mediciones son parecidas a las \(count) anteriores (la diferencia está dentro del margen normal de una medición a otra)."
        }
        if trend.change > 0 {
            return "En tus últimas \(count) mediciones el pulso baja \(difference) lpm más en el primer minuto que en las \(count) anteriores: suele indicar mejor condición. Si a la vez te notas muy cansado, puede ser sobrecarga."
        }
        return "En tus últimas \(count) mediciones el pulso baja \(difference) lpm menos en el primer minuto que en las \(count) anteriores. Puede ser cansancio, calor o que terminaste más fuerte."
    }

    @ViewBuilder
    private var appleSection: some View {
        if let apple = healthReadings.last {
            Divider().overlay(Color.halsynHairline)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recuperación cardíaca de Salud")
                        .font(.halsynCaption.weight(.semibold))
                    Text("La estima el Apple Watch como si terminaras a una intensidad estándar: no se compara directamente con tus mediciones.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
                Spacer()
                Text(verbatim: "\(HalsynFormat.integer(apple.oneMinute))")
                    .font(.halsynHeadline.monospacedDigit())
                Text("lpm")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Text("Cuanto más baja el pulso en el primer minuto, mejor suele ser la condición aeróbica, y con el entrenamiento suele mejorar. Depende de lo fuerte que terminaste, del calor y de si caminas o te quedas quieto: recupera siempre igual y compara mediciones parecidas. De una vez a otra puede variar bastante, así que mira la tendencia. Es un seguimiento de entrenamiento, no una prueba médica.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
            ReferenceLinks(references: [ScienceReferences.recoveryTrainingStatus, ScienceReferences.recoveryMonitoring, ScienceReferences.recoveryOverreaching])
        }
    }
}

/// Curva del pulso de la última recuperación, con marcas a 1 y 2 minutos.
private struct RecoveryCurveChart: View {
    let result: HeartRateRecoveryResult

    private struct Point: Identifiable {
        let id: Int
        let minutes: Double
        let bpm: Double
    }

    private var points: [Point] {
        result.samples.enumerated().map { Point(id: $0.offset, minutes: $0.element.elapsed / 60, bpm: $0.element.bpm) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Minutos", point.minutes), y: .value("lpm", point.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.halsynAlert)
            }
            RuleMark(x: .value("1 min", 1.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.halsynSecondaryText)
            RuleMark(x: .value("2 min", 2.0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.halsynSecondaryText)
        }
        .chartXAxisLabel("min")
        .accessibilityLabel(Text("Curva del pulso de la última recuperación"))
    }
}

/// Bajada del primer minuto en cada medición, con la media móvil de 5.
private struct RecoveryTrendChart: View {
    let readings: [RecoveryReading]

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let average: Double
    }

    private var points: [Point] {
        readings.enumerated().map { index, reading in
            let window = readings[max(0, index - 4)...index].map(\.oneMinute)
            return Point(id: index, date: reading.date, value: reading.oneMinute, average: window.reduce(0, +) / Double(window.count))
        }
    }

    var body: some View {
        Chart(points) { point in
            PointMark(x: .value("Fecha", point.date), y: .value("lpm", point.value))
                .foregroundStyle(Color.halsynChart.opacity(0.6))
            LineMark(x: .value("Fecha", point.date), y: .value("Media", point.average))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.halsynAccent)
        }
        .chartYAxisLabel {
            Text("lpm")
        }
        .accessibilityLabel(Text("Bajada del pulso en el primer minuto en cada medición"))
    }
}
