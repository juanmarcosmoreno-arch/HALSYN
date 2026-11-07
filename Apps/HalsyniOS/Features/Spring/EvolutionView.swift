import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Textos del motor de explicaciones (cada frase sale de un cálculo con su umbral).
enum CoachInsightText {
    static func text(_ insight: CoachInsight, unit: UnitSystem) -> String {
        switch insight {
        case let .fiveKChanged(seconds, weeks):
            let amount = HalsynFormat.duration(abs(seconds))
            return seconds < 0
                ? String(localized: "Tu predicción de 5 km mejoró \(amount) en las últimas \(String(weeks)) semanas.")
                : String(localized: "Tu predicción de 5 km empeoró \(amount) en las últimas \(String(weeks)) semanas.")
        case let .heartRateAtPace(change, pace):
            let bpm = String(Int(abs(change).rounded()))
            let paceText = "\(Pace(secondsPerKilometer: pace).formatted(in: unit)) \(unit.paceUnitSymbol)"
            return change < 0
                ? String(localized: "A igual ritmo (\(paceText)) tu pulso bajó \(bpm) lpm: señal de mejor forma aeróbica.")
                : String(localized: "A igual ritmo (\(paceText)) tu pulso subió \(bpm) lpm: puede ser cansancio, calor o menos forma.")
        case let .tooMuchIntensity(share):
            let percent = String(Int((share * 100).rounded()))
            return String(localized: "Estás acumulando más entrenamiento intenso de lo recomendado: \(percent) % de tus minutos de las últimas 2 semanas (la referencia es cerca del 20 %).")
        case let .volumeChanged(ratio, weekly):
            let percent = String(Int((abs(ratio - 1) * 100).rounded()))
            let distance = SessionText.distance(weekly, unit: unit)
            return ratio > 1
                ? String(localized: "El volumen semanal subió un \(percent) % respecto a tu promedio anterior (ahora \(distance) por semana). Conviene subir de a poco.")
                : String(localized: "El volumen semanal bajó un \(percent) % respecto a tu promedio anterior (ahora \(distance) por semana).")
        case let .restingHeartRateHigh(delta):
            return String(localized: "Tu FC en reposo está \(String(Int(delta.rounded()))) lpm por encima de tu línea basal estos días: puede ser cansancio, poco sueño o algo que se está incubando.")
        case let .recoveryTrend(delta):
            let points = String(Int(abs(delta).rounded()))
            return delta > 0
                ? String(localized: "Tu recuperación de la última semana está \(points) puntos por encima de tu media del mes.")
                : String(localized: "Tu recuperación de la última semana está \(points) puntos por debajo de tu media del mes.")
        case let .consistent(runsPerWeek, weeks):
            let runs = HalsynFormat.decimal(runsPerWeek, fractionDigits: 1)
            return String(localized: "Vienes con regularidad: \(runs) carreras por semana en las últimas \(String(weeks)) semanas.")
        case .lowConfidence:
            return String(localized: "La estimación de tu forma tiene baja confianza porque faltan pruebas recientes: un test la hace más precisa.")
        }
    }

    static func symbol(_ tone: CoachInsight.Tone) -> String {
        switch tone {
        case .positive: "arrow.up.right.circle.fill"
        case .neutral: "info.circle.fill"
        case .caution: "exclamationmark.circle.fill"
        }
    }

    static func color(_ tone: CoachInsight.Tone) -> Color {
        switch tone {
        case .positive: .halsynPositive
        case .neutral: .halsynSecondaryText
        case .caution: .halsynCaution
        }
    }
}

/// Test o competición en el gráfico de forma.
private struct TestPoint: Identifiable {
    let id: UUID
    let date: Date
    let vdot: Double
}

/// Panel de evolución del corredor: lo observado y lo estimado, separados.
struct EvolutionView: View {
    let runs: [WorkoutSummary]
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var period = 4
    @State private var progress: RunnerProgress?
    @State private var insights: [CoachInsight] = []
    @State private var vo2max: [DailyValue] = []
    @State private var recovery: [RecoveryEstimate] = []
    private var fitness: FitnessStore { .shared }

    var body: some View {
        HalsynScreen {
            Picker("Período", selection: $period) {
                Text("4 semanas").tag(4)
                Text("8 semanas").tag(8)
                Text("12 semanas").tag(12)
            }
            .pickerStyle(.segmented)
            if let progress {
                insightsCard
                fitnessCard(progress)
                predictionsCard(progress)
                volumeCard(progress)
                intensityCard(progress)
                heartRateCard(progress)
                recoveryCard
                goalCard
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle("Evolución")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.reloadKey) { await load() }
    }

    private func load() async {
        let today = Date.now
        let built = RunnerProgress.build(runs: runs, results: fitness.results, maxHeartRate: fitness.configuredMaxHeartRate, riegelExponent: fitness.riegelExponent, weeks: 24, today: today, calendar: .current)
        vo2max = await model.provider.dailySeries(.vo2Max, days: 168, endingOn: today).values
        recovery = await model.provider.recoveryEstimates(endingOn: today, days: 28)
        let resting = await model.provider.dailySeries(.restingHeartRate, days: 40, endingOn: today).values
        insights = CoachInsights.generate(progress: built, performance: fitness.performance(runs: runs), restingHeartRate: resting, recovery: recovery.map { (day: $0.day, value: $0.value) }, today: today, calendar: .current)
        progress = built
    }

    private var cutoff: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -period, to: .now) ?? .now
    }

    // MARK: Explicaciones

    private var insightsCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Lo que dicen tus datos", eyebrow: HalsynModule.insikt.brandName)
                if insights.isEmpty {
                    Text("Nada destacable: no hay cambios por encima de los umbrales que usa HÅLSYN para decir algo.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    ForEach(insights) { insight in
                        Label {
                            Text(verbatim: CoachInsightText.text(insight, unit: unitSystem))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: CoachInsightText.symbol(insight.tone))
                                .foregroundStyle(CoachInsightText.color(insight.tone))
                        }
                        .font(.halsynCaption)
                    }
                }
                NavigationLink {
                    ModelAccuracyView(runs: runs)
                } label: {
                    Label("Precisión del modelo contigo", systemImage: "scope")
                        .font(.halsynCaption.weight(.semibold))
                }
                ExpandableText("Cada frase sale de un cálculo con tus datos y solo aparece si el cambio supera un umbral (por ejemplo, 10 s en el 5 km previsto o 3 lpm a igual ritmo). Las reglas están documentadas en la app; no se usa inteligencia artificial.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    // MARK: Forma

    private func fitnessCard(_ progress: RunnerProgress) -> some View {
        let points = progress.modelPoints.filter { $0.date >= cutoff }
        let testPoints = fitness.results.filter { $0.date >= cutoff }.compactMap { result in
            result.vdot.map { TestPoint(id: result.id, date: result.date, vdot: $0) }
        }
        let vo2 = vo2max.filter { $0.day >= cutoff }
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Forma (VDOT)", eyebrow: HalsynLexicon.form.rawValue)
                if points.isEmpty {
                    Text("Sin pruebas suficientes para estimar tu forma en este período.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                } else {
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Fecha", point.date), y: .value("VDOT", point.vdot))
                                .foregroundStyle(by: .value("Serie", String(localized: "Estimado por el modelo")))
                                .interpolationMethod(.monotone)
                        }
                        ForEach(testPoints) { point in
                            PointMark(x: .value("Fecha", point.date), y: .value("VDOT", point.vdot))
                                .foregroundStyle(by: .value("Serie", String(localized: "Observado en tests y carreras")))
                                .symbolSize(60)
                        }
                    }
                    .chartForegroundStyleScale([String(localized: "Estimado por el modelo"): Color.halsynChart, String(localized: "Observado en tests y carreras"): Color.halsynHighlight])
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 170)
                }
                let comparison = PeriodComparison.compare(progress, weeks: period)
                if comparison.isProvisional {
                    Label("Tendencia provisional: menos de 3 tests o competiciones.", systemImage: "hourglass")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
                if let change = comparison.fiveKChange {
                    Text(verbatim: comparison.fiveKChangeIsReal
                         ? String(localized: "El cambio del 5 km previsto (\(HalsynFormat.duration(abs(change)))) supera la variación normal del modelo: es un cambio real.")
                         : String(localized: "El cambio del 5 km previsto (\(HalsynFormat.duration(abs(change)))) está dentro de la variación normal del modelo: todavía no es un cambio claro."))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !vo2.isEmpty {
                    Divider()
                    Text("VO₂ máx. estimado por el Apple Watch")
                        .font(.halsynCaption.weight(.semibold))
                    Chart(vo2) { value in
                        LineMark(x: .value("Fecha", value.day), y: .value("VO₂ máx.", value.value))
                            .foregroundStyle(Color.halsynSecondaryText)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 110)
                }
                ExpandableText("El VDOT es tu forma de carrera según tus esfuerzos a tope (Daniels). El VO₂ máx. lo estima el Apple Watch con otro método: están relacionados, pero no son lo mismo y no tienen por qué coincidir. Los puntos son pruebas reales; la línea, la estimación del modelo.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    // MARK: Predicciones y mejores tiempos

    private func predictionsCard(_ progress: RunnerProgress) -> some View {
        let comparison = PeriodComparison.compare(progress, weeks: period)
        let performance = fitness.performance(runs: runs)
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Tiempos", eyebrow: HalsynLexicon.tid.rawValue)
                if let performance {
                    Text("Estimados por el modelo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                    ForEach(RaceDistance.allCases) { distance in
                        let prediction = performance.predict(distance.rawValue)
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: HalsynFormat.duration(prediction.time)).monospacedDigit()
                                Text(verbatim: "\(prediction.pace.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        } label: {
                            Text(LocalizedStringKey(distance.title))
                        }
                        .font(.halsynCaption)
                    }
                    if let change = comparison.fiveKChange {
                        Text(verbatim: change <= 0
                             ? String(localized: "5 km previsto: \(HalsynFormat.duration(abs(change))) más rápido que hace \(String(period)) semanas.")
                             : String(localized: "5 km previsto: \(HalsynFormat.duration(change)) más lento que hace \(String(period)) semanas."))
                            .font(.caption2)
                            .foregroundStyle(change <= 0 ? Color.halsynPositive : Color.halsynCaution)
                    }
                }
                if !progress.bestEfforts.isEmpty {
                    Divider()
                    Text("Mejores tiempos observados (último año)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                    ForEach(progress.bestEfforts) { effort in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: HalsynFormat.duration(effort.time)).monospacedDigit()
                                Text(effort.date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption2)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        } label: {
                            Text(LocalizedStringKey(effort.distance.title))
                        }
                        .font(.halsynCaption)
                    }
                }
            }
        }
    }

    // MARK: Volumen y regularidad

    private func volumeCard(_ progress: RunnerProgress) -> some View {
        let weeks = Array(progress.weeks.suffix(period))
        let comparison = PeriodComparison.compare(progress, weeks: period)
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Volumen y regularidad", eyebrow: HalsynModule.spring.brandName)
                Chart(weeks) { week in
                    BarMark(x: .value("Semana", week.start, unit: .weekOfYear), y: .value("km", week.distance / unitSystem.metersPerDistanceUnit))
                        .foregroundStyle(Color.halsynChart)
                }
                .frame(height: 140)
                LabeledContent(String(localized: "Por semana"), value: "\(SessionText.distance(comparison.weeklyDistance, unit: unitSystem)) · " + String(localized: "antes \(SessionText.distance(comparison.previousWeeklyDistance, unit: unitSystem))"))
                    .font(.halsynCaption)
                LabeledContent(String(localized: "Carreras por semana"), value: HalsynFormat.decimal(comparison.runsPerWeek, fractionDigits: 1) + " · " + String(localized: "antes \(HalsynFormat.decimal(comparison.previousRunsPerWeek, fractionDigits: 1))"))
                    .font(.halsynCaption)
                LabeledContent(String(localized: "Minutos por semana"), value: HalsynFormat.integer(weeks.map(\.minutes).reduce(0, +) / Double(max(weeks.count, 1))))
                    .font(.halsynCaption)
            }
        }
    }

    // MARK: Intensidad

    private func intensityCard(_ progress: RunnerProgress) -> some View {
        let weeks = Array(progress.weeks.suffix(period))
        let easy = String(localized: "Suave"), moderate = String(localized: "Moderado"), hard = String(localized: "Fuerte")
        let comparison = PeriodComparison.compare(progress, weeks: period)
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Distribución de intensidad", eyebrow: HalsynLexicon.puls.rawValue)
                Chart {
                    ForEach(weeks) { week in
                        BarMark(x: .value("Semana", week.start, unit: .weekOfYear), y: .value("min", week.easyMinutes))
                            .foregroundStyle(by: .value("Tipo", easy))
                        BarMark(x: .value("Semana", week.start, unit: .weekOfYear), y: .value("min", week.moderateMinutes))
                            .foregroundStyle(by: .value("Tipo", moderate))
                        BarMark(x: .value("Semana", week.start, unit: .weekOfYear), y: .value("min", week.hardMinutes))
                            .foregroundStyle(by: .value("Tipo", hard))
                    }
                }
                .chartForegroundStyleScale([easy: Color.halsynPositive, moderate: Color.halsynCaution, hard: Color.halsynAlert])
                .frame(height: 150)
                if let share = comparison.hardShare {
                    Text(verbatim: String(localized: "Fuerte: \(String(Int((share * 100).rounded()))) % de los minutos (referencia: cerca del 20 %)."))
                        .font(.caption2)
                        .foregroundStyle(share > 0.3 ? Color.halsynCaution : Color.halsynSecondaryText)
                }
                ExpandableText("Cada carrera se clasifica por su pulso medio frente a tu FC máxima: suave (< 80 %), moderado (80–87 %), fuerte (≥ 87 %). Las carreras sin pulso no entran. La mayoría de los planes de fondo recomiendan que la mayor parte del tiempo sea suave.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    // MARK: FC a ritmo comparable

    @ViewBuilder
    private func heartRateCard(_ progress: RunnerProgress) -> some View {
        if let pace = progress.referencePace, !progress.comparableHeartRate.isEmpty {
            let points = progress.comparableHeartRate.filter { $0.periodStart >= Calendar.current.date(byAdding: .weekOfYear, value: -max(period, 8), to: .now) ?? .now }
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Pulso a ritmo comparable", eyebrow: HalsynLexicon.puls.rawValue)
                    Chart(points) { point in
                        LineMark(x: .value("Período", point.periodStart), y: .value("lpm", point.heartRate))
                            .foregroundStyle(Color.halsynChart)
                        PointMark(x: .value("Período", point.periodStart), y: .value("lpm", point.heartRate))
                            .foregroundStyle(Color.halsynChart)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 130)
                    Text(verbatim: String(localized: "Pulso estimado a \(Pace(secondsPerKilometer: pace).formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol) en cada período de 4 semanas. Si baja, corres ese ritmo con menos esfuerzo."))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Recuperación y objetivo

    @ViewBuilder
    private var recoveryCard: some View {
        let values = recovery.compactMap(\.value)
        if values.count >= 7 {
            let week = recovery.suffix(7).compactMap(\.value)
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Recuperación", eyebrow: HalsynModule.vila.brandName)
                    LabeledContent(String(localized: "Media de 7 días"), value: week.isEmpty ? "—" : String(week.reduce(0, +) / week.count))
                    LabeledContent(String(localized: "Media de 28 días"), value: String(values.reduce(0, +) / values.count))
                    Text("Indicador orientativo, no un diagnóstico.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
                .font(.halsynCaption)
            }
        }
    }

    @ViewBuilder
    private var goalCard: some View {
        if let plan = TrainingPlanStore.shared.plan,
           let probability = GoalProbability.evaluate(plan: plan, performance: fitness.performance(runs: runs), runs: runs, today: .now, calendar: .current) {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Proximidad al objetivo", eyebrow: HalsynModule.mal.brandName)
                    GoalProbabilitySummary(probability: probability, goal: plan.goal)
                }
            }
        }
    }
}

/// Acceso al panel desde SPRING.
struct EvolutionCard: View {
    let runs: [WorkoutSummary]

    var body: some View {
        NavigationLink {
            EvolutionView(runs: runs)
        } label: {
            HalsynCard {
                HStack(spacing: HalsynSpacing.m) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.halsynAccentText)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evolución")
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text("Forma, tiempos, volumen, intensidad y lo que dicen tus datos")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
