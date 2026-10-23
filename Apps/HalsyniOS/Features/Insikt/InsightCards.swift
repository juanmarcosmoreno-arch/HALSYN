import HalsynCore
import HalsynDesign
import SwiftUI

/// Formato de cada métrica en los textos de INSIKT.
enum InsightFormat {
    private static let beatsPerMinute = NSLocalizedString("lpm", comment: "")

    static func value(_ value: Double, _ metric: MetricKind, unit: UnitSystem = .metric) -> String {
        switch metric {
        case .sleepDuration: sleepText(value * 3600)
        case .restingHeartRate, .heartRate: "\(HalsynFormat.integer(value)) \(beatsPerMinute)"
        case .heartRateVariability: "\(HalsynFormat.integer(value)) ms"
        case .vo2Max: HalsynFormat.decimal(value, fractionDigits: 1)
        case .exerciseTime, .timeInDaylight: "\(HalsynFormat.integer(value)) min"
        case .steps: HalsynFormat.integer(value)
        default: HalsynFormat.decimal(value, fractionDigits: 1)
        }
    }
}

// MARK: - Lo que cambió

struct TrendInsightCard: View {
    let insight: TrendInsight

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Label(LocalizedStringKey(insight.metric.title), systemImage: insight.metric.systemImage)
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    switch insight.isFavorable {
                    case true?: HalsynStatusIndicator(.positive, text: "En buena dirección")
                    case false?: HalsynStatusIndicator(.caution, text: "Conviene vigilarlo")
                    case nil: EmptyView()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: HalsynSpacing.s) {
                    Text(verbatim: InsightFormat.value(insight.previousMean, insight.metric))
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynSecondaryText)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.halsynSecondaryText)
                        .accessibilityHidden(true)
                    Text(verbatim: InsightFormat.value(insight.recentMean, insight.metric))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.halsynPrimaryText)
                }
                HalsynPeriodComparisonChart(
                    values: insight.values,
                    splitDay: insight.splitDay,
                    previousMean: insight.previousMean,
                    recentMean: insight.recentMean,
                    format: { InsightFormat.value($0, insight.metric) }
                )
                .frame(height: 130)
                Text("Media de las últimas 4 semanas frente a las 4 anteriores. Diferencia clara, no explicable por la variación habitual de un día a otro.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }
}

// MARK: - Patrones

struct RelationshipInsightCard: View {
    let insight: RelationshipInsight

    private var predictor: MetricKind { insight.candidate.predictor }
    private var outcome: MetricKind { insight.candidate.outcome }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(spacing: HalsynSpacing.s) {
                    Image(systemName: predictor.systemImage)
                    Image(systemName: "arrow.right").font(.caption)
                    Image(systemName: outcome.systemImage)
                }
                .foregroundStyle(.halsynAccentText)
                .accessibilityHidden(true)
                Text(sentence)
                    .font(.halsynBody)
                    .foregroundStyle(.halsynPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HalsynGroupComparison(
                    lowLabel: String(localized: "Menos de \(threshold)"),
                    highLabel: String(localized: "\(threshold) o más"),
                    lowValue: insight.lowGroupMean,
                    highValue: insight.highGroupMean,
                    format: { InsightFormat.value($0, outcome) }
                )
                let days = insight.pairs
                Text("Observado en \(days) días. Es una asociación en tus datos, no prueba que una cosa cause la otra.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private var threshold: String { InsightFormat.value(insight.threshold, predictor) }
    private var high: String { InsightFormat.value(insight.highGroupMean, outcome) }
    private var low: String { InsightFormat.value(insight.lowGroupMean, outcome) }

    private var sentence: LocalizedStringKey {
        switch (predictor, outcome) {
        case (.sleepDuration, .heartRateVariability):
            "Tras dormir \(threshold) o más, tu HRV fue de \(high) de media; tras dormir menos, de \(low)."
        case (.sleepDuration, .restingHeartRate):
            "Tras dormir \(threshold) o más, tu FC en reposo fue de \(high) de media; tras dormir menos, de \(low)."
        case (.exerciseTime, .heartRateVariability):
            "Al día siguiente de \(threshold) de ejercicio o más, tu HRV fue de \(high) de media; tras días más tranquilos, de \(low)."
        case (.exerciseTime, .restingHeartRate):
            "Al día siguiente de \(threshold) de ejercicio o más, tu FC en reposo fue de \(high) de media; tras días más tranquilos, de \(low)."
        case (.exerciseTime, .sleepDuration):
            "La noche después de \(threshold) de ejercicio o más dormiste \(high) de media; tras días más tranquilos, \(low)."
        case (.timeInDaylight, .sleepDuration):
            "La noche después de \(threshold) de luz natural o más dormiste \(high) de media; tras días con menos luz, \(low)."
        case (.steps, .sleepDuration):
            "La noche después de caminar \(threshold) pasos o más dormiste \(high) de media; tras días con menos pasos, \(low)."
        default:
            "\(high) frente a \(low)"
        }
    }
}

// MARK: - Semana tipo

struct WeekdayInsightCard: View {
    let insight: WeekdayInsight

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                Label(LocalizedStringKey(insight.metric.title), systemImage: insight.metric.systemImage)
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Text(sentence)
                    .font(.halsynBody)
                    .foregroundStyle(.halsynPrimaryText)
                HalsynWeekdayChart(means: insight.means, highlight: insight.highest, format: { InsightFormat.value($0, insight.metric) })
                Text("Media de las últimas 12 semanas por día de la semana.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private var sentence: LocalizedStringKey {
        let best = Calendar.current.weekdaySymbols[insight.highest - 1]
        let worst = Calendar.current.weekdaySymbols[insight.lowest - 1]
        switch insight.metric {
        case .steps: return "Caminas más los \(best) y menos los \(worst)."
        case .exerciseTime: return "Haces más ejercicio los \(best) y menos los \(worst)."
        default: return "Tu sueño es más largo en la noche que termina el \(best) y más corto en la que termina el \(worst)."
        }
    }
}

// MARK: - Récords

struct RecordsCard: View {
    let records: [PersonalRecord]
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tus récords", eyebrow: HalsynModule.insikt.brandName)
                ForEach(records) { record in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: icon(record.kind))
                            // Récords: acento cálido.
                            .foregroundStyle(.halsynHighlight)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(record.kind))
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                            Text(record.date, format: .dateTime.day().month(.wide).year())
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        Spacer()
                        Text(verbatim: value(record))
                            .font(.halsynHeadline.monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                DataOriginFootnote(origin: records.first?.origin)
            }
        }
    }

    private func title(_ kind: PersonalRecord.Kind) -> LocalizedStringKey {
        switch kind {
        case .mostSteps: "Más pasos en un día"
        case .longestRun: "Carrera más larga"
        case .fastestRun: "Ritmo medio más rápido (carreras de 3 km o más)"
        case .highestVO2Max: "VO₂ máx. más alto"
        case .lowestWeeklyRestingHeartRate: "FC en reposo más baja (media de 7 días)"
        }
    }

    private func icon(_ kind: PersonalRecord.Kind) -> String {
        switch kind {
        case .mostSteps: "shoeprints.fill"
        case .longestRun: "point.topleft.down.to.point.bottomright.curvepath"
        case .fastestRun: "speedometer"
        case .highestVO2Max: "lungs"
        case .lowestWeeklyRestingHeartRate: "heart"
        }
    }

    private func value(_ record: PersonalRecord) -> String {
        switch record.kind {
        case .mostSteps: HalsynFormat.integer(record.value)
        case .longestRun: "\(HalsynFormat.distance(meters: record.value, unit: unitSystem)) \(unitSystem.distanceUnitSymbol)"
        case .fastestRun: "\(Pace(secondsPerKilometer: record.value).formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)"
        case .highestVO2Max: HalsynFormat.decimal(record.value, fractionDigits: 1)
        case .lowestWeeklyRestingHeartRate: InsightFormat.value(record.value, .restingHeartRate)
        }
    }
}

// MARK: - Requisitos

struct InsightRequirementsCard: View {
    let requirements: [InsightRequirement]

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Más análisis cuando haya datos")
                ForEach(requirements) { requirement in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(title(requirement))
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynPrimaryText)
                            Spacer()
                            let have = requirement.have
                            let need = requirement.need
                            Text("\(have) de \(need)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        HalsynProgressBar(progress: requirement.progress)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("INSIKT solo muestra una observación cuando hay datos suficientes y la diferencia es clara. Mientras tanto, no inventa conclusiones.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private func title(_ requirement: InsightRequirement) -> LocalizedStringKey {
        let metric = requirement.metric.map { NSLocalizedString($0.title, comment: "") } ?? ""
        switch requirement.analysis {
        case .trends: return "Tendencia de \(metric): días con datos en cada periodo de 4 semanas"
        case .relationships: return "Patrones entre métricas: días con datos emparejados"
        case .weekdays: return "Semana tipo de \(metric): semanas con datos de cada día"
        }
    }
}
