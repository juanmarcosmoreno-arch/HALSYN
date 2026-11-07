import HalsynCore
import HalsynDesign
import SwiftUI

// MARK: - Explicación por reglas

/// Frases del objetivo, todas a partir de los valores calculados (sin números fijos).
enum GoalExplanation {
    static func paragraphs(_ probability: GoalProbability, performance: PerformanceAssessment, goal: PlanGoal, rangeIsCalibrated: Bool, unit: UnitSystem) -> [String] {
        var lines: [String] = []
        let counted = performance.evidence.filter { $0.role == .counted }
        let official = counted.filter { $0.kind != .trainingEffort }.count
        let efforts = counted.count - official
        // 1. De dónde sale el rendimiento actual.
        if efforts > 0 {
            lines.append(String(localized: "Tu rendimiento actual se estima con \(String(official)) tests o competiciones y \(String(efforts)) entrenamientos a tope que superan esa marca. Los rodajes más lentos no lo bajan."))
        } else {
            lines.append(String(localized: "Tu rendimiento actual se estima con \(String(official)) tests o competiciones. Los rodajes más lentos no lo bajan."))
        }
        // 2. Cuánto falta hoy.
        if let goalTime = goal.goalTime {
            let perUnit = unit.metersPerDistanceUnit / 1000
            let change = abs(probability.requiredPaceChange) * perUnit
            let current = Pace(secondsPerKilometer: probability.currentTime / (goal.distance.rawValue / 1000)).formatted(in: unit)
            let target = Pace(secondsPerKilometer: goalTime / (goal.distance.rawValue / 1000)).formatted(in: unit)
            if probability.requiredPaceChange > 0.5 {
                lines.append(String(localized: "Para llegar a \(HalsynFormat.duration(goalTime)) necesitas mejorar unos \(String(Int(change.rounded()))) s por \(unit.distanceUnitSymbol) (de \(current) a \(target) \(unit.paceUnitSymbol))."))
            } else {
                lines.append(String(localized: "Con tu forma de hoy ya corres a \(current) \(unit.paceUnitSymbol), el ritmo del objetivo o mejor."))
            }
        }
        // 3. Proyección y supuestos.
        let gain = HalsynFormat.decimal(probability.expectedGain, fractionDigits: 1)
        let weeksText = String(probability.trainingWeeks)
        let date = goal.raceDate.formatted(.dateTime.day().month(.abbreviated))
        let usesTrend = probability.scenarios.first { $0.scenario == .central }?.usesPersonalTrend ?? false
        let assumption = usesTrend
            ? String(localized: "la mitad según la pauta prudente de Daniels y la mitad según tu tendencia real")
            : String(localized: "según la pauta prudente de Daniels, porque todavía no hay tendencia propia fiable")
        lines.append(String(localized: "La proyección para el \(date) suma unos \(gain) puntos de VDOT en \(weeksText) semanas (\(assumption)), con rendimientos decrecientes y ajustada por cómo cumples el plan. No es una mejora garantizada."))
        // 4. Confianza.
        switch probability.confidence {
        case .high:
            lines.append(String(localized: "La confianza es alta: tienes pruebas recientes y coherentes."))
        case .medium:
            lines.append(official < 3
                         ? String(localized: "La confianza es moderada porque todavía hay pocas pruebas comparables.")
                         : String(localized: "La confianza es moderada: un test reciente la haría más precisa."))
        case .low:
            lines.append(String(localized: "La confianza es baja: faltan pruebas recientes. Un test lo resuelve."))
        }
        // 5. El rango.
        lines.append(rangeIsCalibrated
                     ? String(localized: "Los rangos ya se comprobaron con tus propios resultados.")
                     : String(localized: "Los rangos son orientativos del modelo: todavía no se comprobaron con tus resultados reales, así que no garantizan un 80 % de acierto."))
        return lines
    }
}

// MARK: - Cuatro indicadores

struct GoalIndicatorsView: View {
    let probability: GoalProbability
    let performance: PerformanceAssessment
    let goal: PlanGoal
    let rangeIsCalibrated: Bool
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: HalsynSpacing.m) {
                indicator(String(localized: "Hoy"), value: HalsynFormat.duration(probability.currentTime), detail: probability.currentRange.map(GoalProbabilityText.range))
                indicator(String(localized: "El \(goal.raceDate.formatted(.dateTime.day().month(.abbreviated)))"), value: HalsynFormat.duration(probability.projectedTime), detail: GoalProbabilityText.range(probability.projectedRange))
                indicator(String(localized: "Frente al objetivo"), value: gapText, detail: goal.goalTime.map { String(localized: "Objetivo \(HalsynFormat.duration($0))") }, tint: gapTint)
                indicator(String(localized: "Factibilidad"), value: GoalProbabilityText.titleText(probability.category), detail: GoalProbabilityText.confidence(probability.confidence), tint: GoalProbabilityText.color(probability.category))
            }
            if !rangeIsCalibrated {
                Text("Rangos orientativos del modelo (sin calibrar con tus resultados).")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(GoalExplanation.paragraphs(probability, performance: performance, goal: goal, rangeIsCalibrated: rangeIsCalibrated, unit: unitSystem).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !probability.scenarios.isEmpty {
                ScenariosView(scenarios: probability.scenarios, distance: goal.distance.rawValue)
            }
        }
    }

    private var gapText: String {
        guard let goalTime = goal.goalTime else { return "—" }
        let gap = probability.projectedTime - goalTime
        let text = HalsynFormat.duration(abs(gap))
        return gap > 0 ? "+" + text : "−" + text
    }

    private var gapTint: Color {
        guard let goalTime = goal.goalTime else { return .halsynPrimaryText }
        return probability.projectedTime <= goalTime ? .halsynPositive : .halsynCaution
    }

    private func indicator(_ title: String, value: String, detail: String?, tint: Color = .halsynPrimaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.halsynSecondaryText)
            Text(verbatim: value)
                .font(.halsynHeadline.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(verbatim: detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }
}

/// Escenarios conservador, central y optimista, con su supuesto.
struct ScenariosView: View {
    let scenarios: [GoalProjection.Result]
    let distance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Escenarios")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.halsynSecondaryText)
            ForEach(scenarios, id: \.scenario) { result in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: title(result.scenario))
                            .font(.halsynCaption.weight(.semibold))
                        Text(verbatim: assumption(result))
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(verbatim: HalsynFormat.duration(VDOT.raceTime(vdot: result.projectedVDOT, distance: distance)))
                        .font(.halsynCaption.monospacedDigit())
                }
            }
        }
    }

    private func title(_ scenario: GoalProjection.Scenario) -> String {
        switch scenario {
        case .conservative: String(localized: "Conservador")
        case .central: String(localized: "Central")
        case .optimistic: String(localized: "Optimista")
        }
    }

    private func assumption(_ result: GoalProjection.Result) -> String {
        let weeksText = HalsynFormat.decimal(result.scenario.weeksPerPoint, fractionDigits: 0)
        let compliance = String(Int((result.complianceFactor * 100).rounded()))
        return String(localized: "1 punto de VDOT cada \(weeksText) semanas, \(compliance) % de la mejora por cumplimiento")
    }
}

// MARK: - Adherencia

struct AdherenceView: View {
    let adherence: TrainingAdherence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Adherencia y frecuencia")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.halsynSecondaryText)
            row(String(localized: "Sesiones del plan cumplidas"), value: adherence.planned > 0 ? "\(adherence.done) / \(adherence.planned)" : "—")
            row(String(localized: "Carreras por semana (reales)"), value: HalsynFormat.decimal(adherence.actualRunsPerWeek, fractionDigits: 1))
            row(String(localized: "Carreras por semana (objetivo)"), value: String(adherence.targetRunsPerWeek))
            row(String(localized: "Semanas con plan"), value: String(adherence.weeksWithPlan))
            row(String(localized: "Carreras fuera del plan"), value: String(adherence.runsOutsidePlan))
            if adherence.isLimited {
                Text("El plan empezó hace poco: con pocas sesiones, un 100 % no dice mucho todavía.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let effective = adherence.effective {
                Text(verbatim: String(localized: "Para la proyección cuenta el menor entre cumplir las sesiones y correr las veces del objetivo: \(String(Int((effective * 100).rounded()))) %."))
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.halsynCaption)
    }
}

// MARK: - Simulador

struct GoalSimulatorView: View {
    let runs: [WorkoutSummary]
    let goal: PlanGoal
    let compliance: Double?
    @State private var distance: RaceDistance
    @State private var raceDate: Date
    @State private var goalTime: TimeInterval
    @State private var runsPerWeek: Int
    private var fitness: FitnessStore { .shared }

    init(runs: [WorkoutSummary], goal: PlanGoal, compliance: Double?) {
        self.runs = runs
        self.goal = goal
        self.compliance = compliance
        _distance = State(initialValue: goal.distance)
        _raceDate = State(initialValue: goal.raceDate)
        _goalTime = State(initialValue: goal.goalTime ?? 25 * 60)
        _runsPerWeek = State(initialValue: goal.runsPerWeek)
    }

    var body: some View {
        let performance = fitness.performance(runs: runs)
        let simulation = performance.flatMap { GoalSimulation.run(performance: $0, distance: distance, goalTime: goalTime, raceDate: raceDate, runsPerWeek: runsPerWeek, compliance: compliance, today: .now, calendar: .current) }
        Form {
            Section {
                Picker("Distancia", selection: $distance) {
                    ForEach(RaceDistance.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                DatePicker("Fecha", selection: $raceDate, in: Date.now..., displayedComponents: .date)
                VStack(alignment: .leading) {
                    Text("Tiempo objetivo")
                    DurationPicker(seconds: $goalTime)
                }
                Stepper(value: $runsPerWeek, in: 1...7) {
                    LabeledContent(String(localized: "Carreras por semana"), value: String(runsPerWeek))
                }
            } footer: {
                Text("Cambia lo que quieras: el plan guardado no se toca.")
            }
            if let simulation {
                Section {
                    LabeledContent(String(localized: "Hoy"), value: HalsynFormat.duration(simulation.currentTime))
                    ForEach(simulation.scenarios, id: \.scenario) { result in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: HalsynFormat.duration(simulation.time(result))).monospacedDigit()
                                Text(verbatim: GoalProbabilityText.range(simulation.range(result)))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        } label: {
                            Text(verbatim: scenarioTitle(result.scenario))
                        }
                    }
                    LabeledContent(String(localized: "Factibilidad"), value: GoalProbabilityText.titleText(simulation.category))
                } header: {
                    Text("Resultado")
                } footer: {
                    Text(verbatim: changesText(simulation))
                }
            } else {
                Section {
                    Text("Hace falta un test o una competición para simular.")
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .navigationTitle("Simulador")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scenarioTitle(_ scenario: GoalProjection.Scenario) -> String {
        switch scenario {
        case .conservative: String(localized: "Conservador")
        case .central: String(localized: "Central")
        case .optimistic: String(localized: "Optimista")
        }
    }

    /// Qué cambió frente al plan y cómo afecta (supuestos explícitos).
    private func changesText(_ simulation: GoalSimulation) -> String {
        var parts: [String] = []
        parts.append(String(localized: "\(String(simulation.weeks)) semanas de entrenamiento hasta la carrera."))
        if runsPerWeek != goal.runsPerWeek {
            let factor = String(Int((GoalProjection.frequencyFactor(runsPerWeek: runsPerWeek) * 100).rounded()))
            parts.append(String(localized: "Con \(String(runsPerWeek)) carreras por semana cuenta el \(factor) % de la mejora esperada (4 o más: 100 %; más días no suman)."))
        }
        if simulation.scenarios.count == 1 {
            parts.append(String(localized: "Con confianza baja solo se muestra el escenario central."))
        }
        parts.append(String(localized: "Escenarios: 1 punto de VDOT cada 12 (conservador), 6 (central) o 4 semanas (optimista), con rendimientos decrecientes. No son promesas."))
        return parts.joined(separator: " ")
    }
}
