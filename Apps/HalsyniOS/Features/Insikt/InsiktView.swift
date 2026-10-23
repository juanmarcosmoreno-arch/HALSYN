import HalsynCore
import HalsynDesign
import SwiftUI

/// Periodos de análisis.
enum InsiktPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90
    case halfYear = 180
    case year = 365

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "7 d"
        case .month: "30 d"
        case .quarter: "90 d"
        case .halfYear: "180 d"
        case .year: "1 año"
        }
    }
}

/// Tendencia de una métrica en el periodo y en el periodo anterior equivalente.
struct InsiktTrend: Identifiable, Sendable {
    let kind: MetricKind
    let current: MetricSeries
    let previousAverage: Double?

    var id: MetricKind { kind }

    /// Cambio relativo de la media frente al periodo anterior, si ambos existen.
    var relativeChange: Double? {
        guard let now = current.average, let before = previousAverage, before != 0 else { return nil }
        return (now - before) / before
    }
}

/// INSIKT — análisis longitudinal: qué cambió, patrones entre métricas, semana
/// tipo y récords (`InsightEngine`, solo con datos suficientes), más las
/// tendencias por periodo.
struct InsiktView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var period: InsiktPeriod = .month
    @State private var trends: [InsiktTrend]?
    @State private var scores: [DailyScore] = []
    @State private var report: InsightReport?

    static let metrics: [MetricKind] = [.restingHeartRate, .heartRateVariability, .vo2Max, .sleepDuration, .steps, .walkingRunningDistance]

    var body: some View {
        NavigationStack {
            HalsynScreen {
                ModuleHeader(module: .insikt, isDemo: model.isDemo)
                    .padding(.top, HalsynSpacing.s)

                if let report {
                    insights(report)
                } else {
                    HalsynLoadingState()
                }

                HalsynSectionHeader("Tendencias por periodo", eyebrow: HalsynLexicon.tid.rawValue)
                    .padding(.top, HalsynSpacing.s)
                Picker("Periodo", selection: $period) {
                    ForEach(InsiktPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                if let trends {
                    if !scores.isEmpty {
                        scoreCard
                    }
                    ForEach(trends) { trend in
                        trendCard(trend)
                    }
                    NavigationLink {
                        VilaView()
                    } label: {
                        moduleLink(.vila)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        MalView()
                    } label: {
                        moduleLink(.mal)
                    }
                    .buttonStyle(.plain)
                    HalsynCard {
                        HStack {
                            Text("Comparación con tu grupo de edad")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                            Spacer()
                            PhaseTag(phase: 8)
                        }
                    }
                } else {
                    HalsynLoadingState()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: model.reloadKey) {
                report = await model.provider.computeInsights(endingOn: .now, calendar: .current, origin: model.isDemo ? .demo : .derived(engine: "InsightEngine"))
            }
            .task(id: "\(period.rawValue)|\(model.reloadKey)") {
                trends = await load(period: period)
                scores = await model.provider.dailyScores(endingOn: .now, days: period.rawValue)
            }
        }
    }

    @ViewBuilder
    private func insights(_ report: InsightReport) -> some View {
        if !report.trends.isEmpty {
            HalsynSectionHeader("Lo que cambió", eyebrow: HalsynModule.insikt.brandName)
            ForEach(report.trends) { TrendInsightCard(insight: $0) }
        }
        if !report.relationships.isEmpty {
            HalsynSectionHeader("Patrones en tus datos", eyebrow: HalsynModule.insikt.brandName)
            ForEach(report.relationships) { RelationshipInsightCard(insight: $0) }
        }
        if !report.weekdays.isEmpty {
            HalsynSectionHeader("Tu semana tipo", eyebrow: HalsynLexicon.tid.rawValue)
            ForEach(report.weekdays) { WeekdayInsightCard(insight: $0) }
        }
        if report.trends.isEmpty && report.relationships.isEmpty && report.weekdays.isEmpty {
            HalsynCard {
                HalsynEmptyState(systemImage: "sparkle.magnifyingglass", title: "Nada destacable por ahora", message: "No hay cambios ni patrones claros en tus datos. Es normal: INSIKT solo habla cuando la diferencia es real.")
            }
        }
        if !report.records.isEmpty {
            RecordsCard(records: report.records)
        }
        if !report.requirements.isEmpty {
            InsightRequirementsCard(requirements: report.requirements)
        }
        if report.origin?.isDemo == true {
            DataOriginFootnote(origin: .demo, extra: "Patrones de ejemplo generados para la demostración.")
        }
    }

    private func load(period: InsiktPeriod) async -> [InsiktTrend] {
        let today = Date.now
        let previousEnd = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: today) ?? today
        var result: [InsiktTrend] = []
        for kind in Self.metrics {
            let current = await model.provider.dailySeries(kind, days: period.rawValue, endingOn: today)
            let previous = await model.provider.dailySeries(kind, days: period.rawValue, endingOn: previousEnd)
            result.append(InsiktTrend(kind: kind, current: current, previousAverage: previous.average))
        }
        return result
    }

    private var scoreCard: some View {
        let average = Double(scores.map(\.value).reduce(0, +)) / Double(max(scores.count, 1))
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                Label("Puntuación diaria", systemImage: "sparkles")
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                HalsynTrendChart(values: scores.map { DailyValue(day: $0.day, value: Double($0.value)) }, title: "Puntuación", yDomain: 0...100, usualRange: usualRange(scores.map { Double($0.value) }))
                    .frame(height: 210)
                HalsynMetric(title: "Media del periodo", value: HalsynFormat.integer(average), unit: "")
                DataOriginFootnote(origin: scores.first?.origin)
            }
        }
    }

    private func trendCard(_ trend: InsiktTrend) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Label(LocalizedStringKey(trend.kind.title), systemImage: trend.kind.systemImage)
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    if let change = trend.relativeChange {
                        Text(change, format: .percent.precision(.fractionLength(0)).sign(strategy: .always()))
                            .font(.halsynCaption.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                            .accessibilityLabel(Text("Cambio frente al periodo anterior"))
                            .accessibilityValue(Text(change, format: .percent.precision(.fractionLength(0)).sign(strategy: .always())))
                    }
                }
                HalsynTrendChart(values: displayValues(trend), title: trend.kind.shortTitle, style: trend.kind.dailyAggregation == .sum && period == .week ? .bar : .line, unit: trend.kind == .sleepDuration ? "" : HalsynFormat.unitSymbol(for: trend.kind, unit: unitSystem), format: { trend.kind == .sleepDuration ? sleepText($0 * 3600) : (trend.kind == .walkingRunningDistance ? HalsynFormat.decimal($0, fractionDigits: 2) : HalsynFormat.integer($0)) })
                    .frame(height: 210)
                if let average = trend.current.average {
                    HalsynMetric(title: "Media del periodo", value: HalsynFormat.metricValue(average, kind: trend.kind, unit: unitSystem), unit: HalsynFormat.unitSymbol(for: trend.kind, unit: unitSystem))
                }
                DataOriginFootnote(origin: trend.current.origin)
            }
        }
    }

    private func displayValues(_ trend: InsiktTrend) -> [DailyValue] {
        guard trend.kind == .walkingRunningDistance else { return trend.current.values }
        return trend.current.values.map { DailyValue(day: $0.day, value: $0.value / unitSystem.metersPerDistanceUnit) }
    }

    private func moduleLink(_ module: HalsynModule) -> some View {
        HalsynCard {
            HStack(spacing: HalsynSpacing.m) {
                Image(systemName: module.systemImage)
                    .font(.title3)
                    .foregroundStyle(.halsynAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: module.brandName).halsynEyebrowStyle()
                    Text(LocalizedStringKey(module.summary))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.halsynSecondaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    InsiktView()
        .environment(AppModel())
}
