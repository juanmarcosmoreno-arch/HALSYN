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
                        HalsynMetric(title: "Hoy", value: current.value, unit: current.unit)
                        if let status = current.status {
                            HalsynStatusIndicator(.neutral, text: status)
                        }
                    } else {
                        HalsynLoadingState()
                    }
                }
            }

            if let series {
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                        HalsynSectionHeader("Últimos 30 días")
                        HalsynTrendChart(values: displayValues(series), title: kind.shortTitle, style: kind.dailyAggregation == .sum ? .bar : .line)
                            .frame(height: 180)
                        if let average = series.average {
                            HalsynMetric(title: "Tu media del periodo", value: HalsynFormat.metricValue(average, kind: kind, unit: unitSystem), unit: HalsynFormat.unitSymbol(for: kind, unit: unitSystem))
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
                    Text("La comparación con personas de tu edad llegará en la Fase 8, solo con referencias científicas verificadas.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey(kind.title)))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: unitSystem) {
            let today = Date.now
            current = MetricDisplay(await model.provider.latest(kind, on: today), kind: kind, unitSystem: unitSystem)
            series = await model.provider.dailySeries(kind, days: 30, endingOn: today)
        }
    }

    /// Convierte valores a la unidad mostrada (distancia en km/mi, SpO₂ en %).
    private func displayValues(_ series: MetricSeries) -> [DailyValue] {
        series.values.map { item -> DailyValue in
            switch kind {
            case .walkingRunningDistance: DailyValue(day: item.day, value: item.value / unitSystem.metersPerDistanceUnit)
            case .oxygenSaturation: DailyValue(day: item.day, value: item.value * 100)
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
        }
    }
}
