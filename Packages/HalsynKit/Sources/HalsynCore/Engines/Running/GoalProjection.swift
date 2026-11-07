import Foundation

/// Adherencia y frecuencia de entrenamiento, separadas (no es lo mismo cumplir
/// el 100 % de 3 sesiones que correr las 4 veces por semana del objetivo).
public struct TrainingAdherence: Hashable, Sendable {
    /// Sesiones de carrera del plan ya pasadas en la ventana.
    public let planned: Int
    public let done: Int
    /// Hechas = 1, en parte = fracción corrida (máx. 0,8), no hechas = 0.
    public let score: Double
    /// Carreras por semana del objetivo del plan.
    public let targetRunsPerWeek: Int
    /// Carreras reales por semana en la ventana (dentro y fuera del plan).
    public let actualRunsPerWeek: Double
    /// Semanas que abarca la ventana (desde el inicio del plan, como mucho 4).
    public let windowWeeks: Double
    /// Semanas del plan ya empezadas.
    public let weeksWithPlan: Int
    /// Carreras en días sin sesión de carrera en el plan.
    public let runsOutsidePlan: Int

    /// Fracción de las sesiones programadas que hiciste (`nil` sin sesiones pasadas).
    public var planAdherence: Double? { planned > 0 ? score / Double(planned) : nil }
    /// Frecuencia real frente a la del objetivo (máx. 1).
    public var frequencyRatio: Double { targetRunsPerWeek > 0 ? min(actualRunsPerWeek / Double(targetRunsPerWeek), 1) : 1 }
    /// Lo que se usa para la mejora esperada: el menor entre adherencia y frecuencia.
    public var effective: Double? { planAdherence.map { min($0, frequencyRatio) } }
    /// Menos de 2 semanas o menos de 4 sesiones: dato todavía limitado.
    public var isLimited: Bool { windowWeeks < 2 || planned < 4 }

    public static let windowDays = 28

    public static func evaluate(plan: TrainingPlan, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> TrainingAdherence {
        let todayStart = calendar.startOfDay(for: today)
        let planStart = plan.weeks.first.map { calendar.startOfDay(for: $0.start) } ?? todayStart
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) ?? todayStart
        let windowStart = max(planStart, fourWeeksAgo)
        let days = max(calendar.dateComponents([.day], from: windowStart, to: todayStart).day ?? 0, 0)
        let sessions = plan.weeks.flatMap(\.sessions).filter { $0.date >= windowStart && calendar.startOfDay(for: $0.date) < todayStart }
        let running = sessions.filter { $0.kind != .rest }
        var score = 0.0
        var done = 0
        for session in running {
            switch SessionCompletion.evaluate(session, runs: runs, today: today, calendar: calendar) {
            case .done:
                score += 1
                done += 1
            case let .partial(distance):
                score += session.distance > 0 ? min(distance / session.distance, 0.8) : 0.5
            default:
                break
            }
        }
        let windowRuns = runs.filter { $0.activity.isRun && $0.start >= windowStart && $0.start < todayStart }
        let runDays = Set(running.map { calendar.startOfDay(for: $0.date) })
        let outside = windowRuns.filter { !runDays.contains(calendar.startOfDay(for: $0.start)) }.count
        let weeks = Double(days) / 7
        let started = plan.weeks.filter { $0.start <= today }.count
        return TrainingAdherence(
            planned: running.count,
            done: done,
            score: score,
            targetRunsPerWeek: plan.goal.runsPerWeek,
            actualRunsPerWeek: weeks >= 1 ? Double(windowRuns.count) / weeks : Double(windowRuns.count),
            windowWeeks: weeks,
            weeksWithPlan: started,
            runsOutsidePlan: outside
        )
    }
}

/// Proyección de la forma hasta una fecha, con supuestos explícitos.
///
/// Supuestos (RUNNING_ENGINE.md, "Proyección"):
/// - **Ritmo de mejora** (puntos de VDOT por semana de entrenamiento constante),
///   según la pauta de Daniels de 1 punto cada 4–6 semanas:
///   conservador 1/12 (la mitad de la prudente), central 1/6, optimista 1/4.
///   En el central, con 3 tests o más y tendencia no provisional, la mitad
///   del ritmo sale de tu tendencia real (acotada a 0–0,25).
/// - **Rendimientos decrecientes**: mejora = 4 × (1 − e^(−semanas × ritmo × factor / 4)).
///   Cerca del principio es casi lineal; luego se aplana (tope de 4 puntos en
///   un bloque de preparación). Es un supuesto de HÅLSYN, no una ley.
/// - **Factor de cumplimiento**: adherencia efectiva (menor entre sesiones
///   cumplidas y frecuencia real); ≥ 90 % cuenta entera, ≤ 40 % nada. Sin
///   datos: 70 % (conservador), 85 % (central), 95 % (optimista).
/// - **Frecuencia** (simulador): 1 día/semana 0,4; 2 → 0,6; 3 → 0,85; 4 o más → 1.
///   Más días no suman por encima de 4: no se promete que entrenar más sea mejor.
/// - **Incertidumbre** de la proyección = √(forma hoy² + (½ mejora)² +
///   (0,15 × √semanas)² + 0,7² del día de la carrera): crece con el tiempo
///   que falta aunque la mejora esperada sea pequeña.
public enum GoalProjection {
    public enum Scenario: Int, CaseIterable, Hashable, Sendable {
        case conservative, central, optimistic

        public var weeksPerPoint: Double {
            switch self {
            case .conservative: 12
            case .central: 6
            case .optimistic: 4
            }
        }

        public var assumedCompliance: Double {
            switch self {
            case .conservative: 0.7
            case .central: 0.85
            case .optimistic: 0.95
            }
        }
    }

    public struct Result: Hashable, Sendable {
        public let scenario: Scenario
        public let weeks: Int
        public let rate: Double
        public let complianceFactor: Double
        public let frequencyFactor: Double
        public let gain: Double
        public let projectedVDOT: Double
        public let uncertainty: Double
        public let usesPersonalTrend: Bool
    }

    public static let improvementCap = 4.0
    public static let horizonUncertaintyPerRootWeek = 0.15
    public static let raceDayUncertainty = 0.7

    public static func frequencyFactor(runsPerWeek: Int) -> Double {
        switch runsPerWeek {
        case ..<1: 0
        case 1: 0.4
        case 2: 0.6
        case 3: 0.85
        default: 1
        }
    }

    public static func gain(weeks: Int, rate: Double, factor: Double) -> Double {
        guard weeks > 0, rate > 0, factor > 0 else { return 0 }
        return improvementCap * (1 - exp(-Double(weeks) * rate * factor / improvementCap))
    }

    public static func project(performance: PerformanceAssessment, weeks: Int, compliance: Double?, runsPerWeek: Int, scenario: Scenario) -> Result {
        var rate = 1 / scenario.weeksPerPoint
        var personal = false
        if scenario == .central, !performance.trendIsProvisional, let trend = performance.weeklyTrend {
            rate = 0.5 * rate + 0.5 * min(max(trend, 0), RacePerformanceModel.maximumWeeklyTrend)
            personal = true
        }
        let complianceFactor = GoalProbability.gainFactor(compliance ?? scenario.assumedCompliance)
        let frequency = frequencyFactor(runsPerWeek: runsPerWeek)
        let gain = gain(weeks: weeks, rate: rate, factor: complianceFactor * frequency)
        var gainSigma = 0.5 * gain
        if compliance == nil { gainSigma += 0.3 }
        let horizon = horizonUncertaintyPerRootWeek * Double(max(weeks, 0)).squareRoot()
        let sigma = (performance.uncertainty * performance.uncertainty + gainSigma * gainSigma + horizon * horizon + raceDayUncertainty * raceDayUncertainty).squareRoot()
        return Result(scenario: scenario, weeks: weeks, rate: rate, complianceFactor: complianceFactor, frequencyFactor: frequency, gain: gain, projectedVDOT: performance.currentVDOT + gain, uncertainty: sigma, usesPersonalTrend: personal)
    }
}

/// Simulador de objetivos: misma proyección con otra distancia, fecha,
/// tiempo o días por semana. Muestra qué supuestos cambian, no promete nada.
public struct GoalSimulation: Hashable, Sendable {
    public let distance: Double
    public let goalTime: TimeInterval
    public let raceDate: Date
    public let runsPerWeek: Int
    public let weeks: Int
    /// Tiempo con tu forma de hoy.
    public let currentTime: TimeInterval
    /// Escenarios (solo el central si la confianza es baja).
    public let scenarios: [GoalProjection.Result]
    public let category: GoalProbability.Category

    public func time(_ result: GoalProjection.Result) -> TimeInterval {
        VDOT.raceTime(vdot: result.projectedVDOT, distance: distance)
    }

    public func range(_ result: GoalProjection.Result) -> ClosedRange<TimeInterval> {
        VDOT.raceTime(vdot: result.projectedVDOT + 1.28 * result.uncertainty, distance: distance)...VDOT.raceTime(vdot: max(result.projectedVDOT - 1.28 * result.uncertainty, 15), distance: distance)
    }

    public static func run(performance: PerformanceAssessment, distance: RaceDistance, goalTime: TimeInterval, raceDate: Date, runsPerWeek: Int, compliance: Double?, today: Date, calendar: Calendar) -> GoalSimulation? {
        guard let goalVDOT = VDOT.value(distance: distance.rawValue, time: goalTime) else { return nil }
        let weeks = GoalCoach.trainingWeeks(until: raceDate, distance: distance, today: today, calendar: calendar)
        let wanted: [GoalProjection.Scenario] = performance.confidence >= .medium ? GoalProjection.Scenario.allCases : [.central]
        let scenarios = wanted.map { GoalProjection.project(performance: performance, weeks: weeks, compliance: compliance, runsPerWeek: runsPerWeek, scenario: $0) }
        guard let central = scenarios.first(where: { $0.scenario == .central }) else { return nil }
        let z = (central.projectedVDOT - goalVDOT) / central.uncertainty
        let category: GoalProbability.Category = z >= 1 ? .veryLikely : (z >= 0 ? .achievable : (z >= -1 ? .demanding : .unrealistic))
        return GoalSimulation(distance: distance.rawValue, goalTime: goalTime, raceDate: raceDate, runsPerWeek: runsPerWeek, weeks: weeks, currentTime: VDOT.raceTime(vdot: performance.currentVDOT, distance: distance.rawValue), scenarios: scenarios, category: category)
    }
}
