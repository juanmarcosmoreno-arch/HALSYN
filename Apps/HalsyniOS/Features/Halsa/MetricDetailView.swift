import HalsynCore
import HalsynDesign
import SwiftUI

/// Detalle de un indicador: valor actual, evolución, comparación personal,
/// explicación y origen del dato.
struct MetricDetailView: View {
    let kind: MetricKind

    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var current: MetricDisplay?
    @State private var series: MetricSeries?

    var body: some View {
        HalsynScreen {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HStack {
                        Label(kind.lexicon?.rawValue ?? kind.shortTitle.uppercased(), systemImage: kind.systemImage)
                            .halsynEyebrowStyle()
                        Spacer()
                        if model.isDemo { HalsynDemoBadge() }
                    }
                    if let current {
                        HalsynMetric(title: isToday(current.date) ? "Hoy" : "Último registro", value: current.value, unit: current.unit)
                        if let date = current.date, !isToday(date) {
                            Text(date, format: .dateTime.day().month(.wide).year())
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        if let status = current.status {
                            HalsynStatusIndicator(.neutral, text: status)
                            if !model.isDemo {
                                HealthAccessHint()
                            }
                        }
                        DataOriginFootnote(origin: current.origin)
                    } else {
                        HalsynLoadingState()
                    }
                }
            }

            if let series {
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                        HalsynSectionHeader("Últimos 30 días")
                        let all = displayValues(series)
                        let cutoff = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now)) ?? .now
                        let shown = all.filter { $0.day >= cutoff }
                        let isSum = kind.dailyAggregation == .sum
                        HalsynTrendChart(
                            values: shown,
                            title: kind.shortTitle,
                            style: isSum ? .bar : .line,
                            // Indicadores fisiológicos: tu rango habitual de los 30 días anteriores.
                            usualRange: isSum ? nil : usualRange(all.filter { $0.day < cutoff }.map(\.value)),
                            target: kind == .steps ? HealthScoreConfiguration().stepsReference : nil,
                            unit: kind == .sleepDuration ? "" : HalsynFormat.unitSymbol(for: kind, unit: unitSystem),
                            format: { formatted($0) }
                        )
                        .frame(height: 230)
                        if !shown.isEmpty {
                            let average = shown.map(\.value).reduce(0, +) / Double(shown.count)
                            HalsynMetric(title: "Tu media del periodo", value: formatted(average), unit: kind == .sleepDuration ? "" : HalsynFormat.unitSymbol(for: kind, unit: unitSystem))
                        }
                        DataOriginFootnote(origin: series.origin)
                    }
                }
            }

            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Qué mide")
                    Text(LocalizedStringKey(MetricExplanation.text(for: kind)))
                        .font(.halsynBody)
                        .foregroundStyle(.halsynPrimaryText)
                }
            }

            if kind.hasAgeReference {
                ReferenceComparisonCard(kind: kind)
            } else if kind == .heartRateVariability {
                NoAgeReferenceNote()
            }
        }
        .navigationTitle(Text(LocalizedStringKey(kind.title)))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(unitSystem.rawValue)|\(model.reloadKey)") {
            let today = Date.now
            current = MetricDisplay(await model.provider.latest(kind, on: today), kind: kind, unitSystem: unitSystem)
            series = await model.provider.dailySeries(kind, days: 60, endingOn: today)
        }
    }

    private func isToday(_ date: Date?) -> Bool {
        date.map { Calendar.current.isDateInToday($0) } ?? true
    }

    /// Valor ya convertido a la unidad mostrada.
    private func formatted(_ value: Double) -> String {
        switch kind {
        case .walkingRunningDistance: HalsynFormat.decimal(value, fractionDigits: 2)
        case .sleepDuration: sleepText(value * 3600)
        case .respiratoryRate, .vo2Max, .bodyMass, .leanBodyMass, .bodyFatPercentage: HalsynFormat.decimal(value, fractionDigits: 1)
        default: HalsynFormat.integer(value)
        }
    }

    /// Convierte valores a la unidad mostrada (distancia en km/mi, SpO₂ en %).
    private func displayValues(_ series: MetricSeries) -> [DailyValue] {
        series.values.map { item -> DailyValue in
            switch kind {
            case .walkingRunningDistance: DailyValue(day: item.day, value: item.value / unitSystem.metersPerDistanceUnit)
            case .oxygenSaturation, .bodyFatPercentage: DailyValue(day: item.day, value: item.value * 100)
            case .bodyMass, .leanBodyMass: DailyValue(day: item.day, value: item.value / unitSystem.kilogramsPerMassUnit)
            default: item
            }
        }
    }
}

/// Explicaciones divulgativas, sin afirmaciones clínicas.
enum MetricExplanation {
    static func text(for kind: MetricKind) -> String {
        switch kind {
        case .heartRate:
            "Latidos por minuto medidos por el sensor óptico del Apple Watch a lo largo del día."
        case .restingHeartRate:
            "Estimación de Apple de tus pulsaciones cuando estás quieto y relajado. Es más útil compararla con tu propio rango habitual que con un valor fijo."
        case .heartRateVariability:
            "Variación en el tiempo entre latidos (SDNN, en milisegundos). Cambia mucho entre personas y de un día a otro; lo relevante son las tendencias personales."
        case .respiratoryRate:
            "Respiraciones por minuto estimadas durante el sueño."
        case .vo2Max:
            "Estimación de Apple de tu capacidad aeróbica máxima a partir de caminatas y carreras al aire libre. No es una prueba de laboratorio."
        case .oxygenSaturation:
            "Porcentaje de oxígeno en sangre estimado por el reloj en modelos compatibles. No sirve para uso médico."
        case .steps:
            "Pasos registrados por el iPhone y el Apple Watch, sin duplicados."
        case .walkingRunningDistance:
            "Distancia recorrida caminando o corriendo."
        case .activeEnergy:
            "Energía estimada que gastas al moverte, además de la energía en reposo."
        case .exerciseTime:
            "Minutos con intensidad equivalente a una caminata enérgica o superior, según Apple."
        case .sleepDuration:
            "Tiempo dormido registrado por el Apple Watch u otras fuentes de Apple Health."
        case .bodyMass:
            "Último peso registrado en Apple Health, por ejemplo desde una balanza conectada. El peso cambia 1–2 kg de un día a otro por agua y comida: mira la tendencia de semanas."
        case .bodyFatPercentage:
            "Estimación de la balanza por bioimpedancia. Varía con la hidratación y la hora; compárala siempre en las mismas condiciones (por ejemplo, al levantarte)."
        case .leanBodyMass:
            "Todo lo que no es grasa: músculo, huesos, órganos y agua. La calcula la balanza a partir de la bioimpedancia."
        }
    }
}
