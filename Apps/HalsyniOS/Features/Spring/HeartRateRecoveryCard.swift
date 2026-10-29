import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// "Recuperación del pulso": cuánto baja la FC en el primer minuto (y a los
/// 2 minutos, en las de HÅLSYN) después de terminar, y su evolución.
/// Lee lo guardado en Apple Health: las mediciones de HÅLSYN y las del Apple Watch.
struct HeartRateRecoveryCard: View {
    @Environment(AppModel.self) private var model
    @State private var readings: [RecoveryReading]?

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Recuperación del pulso", eyebrow: HalsynLexicon.puls.rawValue)
                if let readings {
                    if let last = readings.last {
                        content(readings, last: last)
                    } else {
                        Text("Al terminar una carrera en el reloj, elige «Guardar y medir recuperación» y camina despacio: el reloj mide cuánto baja tu pulso en 1 y 2 minutos y te pregunta si guardarlo.")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynPrimaryText)
                    }
                    explanation
                } else {
                    HalsynLoadingState()
                }
            }
        }
        .task(id: model.reloadKey) {
            readings = await model.provider.heartRateRecoveries(days: 180)
        }
    }

    @ViewBuilder
    private func content(_ readings: [RecoveryReading], last: RecoveryReading) -> some View {
        HStack(alignment: .top) {
            HalsynMetric(title: "1 min", value: "−\(HalsynFormat.integer(last.oneMinute))", unit: "lpm")
            Spacer()
            HalsynMetric(title: "2 min", value: last.twoMinutes.map { "−\(HalsynFormat.integer($0))" }, unit: "lpm")
            Spacer()
            HalsynMetric(title: "Al terminar", value: last.endHeartRate.map { HalsynFormat.integer($0) }, unit: "lpm", alignment: .trailing)
        }
        Text(last.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
            .font(.caption2)
            .foregroundStyle(.halsynSecondaryText)
        if readings.count > 1 {
            RecoveryTrendChart(readings: readings)
                .frame(height: 140)
        }
        if let trend = RecoveryTrend.make(readings) {
            Text(trendText(trend))
                .font(.halsynCaption)
                .foregroundStyle(.halsynPrimaryText)
        } else {
            let count = max(0, 10 - readings.count)
            Text("Con \(count) mediciones más se ve si tu recuperación mejora.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
        if readings.contains(where: { $0.twoMinutes == nil }) {
            Text("Las del Apple Watch (Recuperación cardíaca de Salud) solo traen el primer minuto.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        DataOriginFootnote(origin: last.origin)
    }

    private func trendText(_ trend: RecoveryTrend) -> LocalizedStringKey {
        let difference = HalsynFormat.integer(abs(trend.change))
        let count = trend.count
        if trend.change >= 2 {
            return "En tus últimas \(count) mediciones el pulso baja \(difference) lpm más en el primer minuto que en las \(count) anteriores: recuperas más rápido."
        } else if trend.change <= -2 {
            return "En tus últimas \(count) mediciones el pulso baja \(difference) lpm menos en el primer minuto que en las \(count) anteriores. Puede ser cansancio, calor o que terminaste más fuerte."
        }
        return "Tus últimas \(count) mediciones son parecidas a las \(count) anteriores."
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
            Text("Cuanto más baja el pulso en el primer minuto, mejor suele ser la condición aeróbica; con el entrenamiento suele mejorar. Depende de lo fuerte que terminaste, del calor y de si caminas o te quedas quieto: compara mediciones parecidas. Es un seguimiento de entrenamiento, no una prueba médica.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
            ReferenceLinks(references: [ScienceReferences.recoveryTrainingStatus, ScienceReferences.recoveryMonitoring])
        }
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
