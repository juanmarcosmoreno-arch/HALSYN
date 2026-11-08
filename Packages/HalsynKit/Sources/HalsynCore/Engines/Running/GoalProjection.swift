import Foundation

/// Por qué no se hizo una sesión del plan. Enfermedad y lesión no cuentan
/// como incumplimiento (no se penaliza estar enfermo); viaje, falta de tiempo
/// u otro motivo sí cuentan como sesión no hecha, pero quedan registrados.
public enum SessionSkipReason: String, Codable, CaseIterable, Hashable, Sendable {
    case illness, injury, travel, time, other

    /// No cuenta en la adherencia.
    public var isExcused: Bool { self == .illness || self == .injury }
}

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
    /// Días con carrera por semana en la ventana (dentro y fuera del plan;
    /// registros de menos de 1 km o del mismo día cuentan una vez).
    public let actualRunsPerWeek: Double
    /// Semanas que abarca la ventana (desde el inicio del plan, como mucho 4).
    public let windowWeeks: Double
    /// Semanas del plan ya empezadas.
    public let weeksWithPlan: Int
    /// Días con carrera sin sesión de carrera en el plan.
    public let runsOutsidePlan: Int
    /// Sesiones hechas en parte (cuentan una fracción).
    public var partial: Int = 0
    /// Sesiones no hechas que sí cuentan (sin motivo, viaje, tiempo u otro).
    public var missed: Int = 0
    /// Sesiones no hechas por enfermedad o lesión (no cuentan).
    public var excused: Int = 0
    /// Motivos registrados de las sesiones no hechas.
    public var skipReasons: [SessionSkipReason: Int] = [:]

    /// «3 / 3 · 100 %» (hechas / programadas que cuentan · cumplimiento con las
    /// parciales), o `nil` sin sesiones pasadas.
    public var sessionsSummary: String? {
        guard planned > 0, let fraction = planAdherence else { return nil }
        return "\(done) / \(planned) · \(Int((fraction * 100).rounded())) %"
    }

    /// Fracción de las sesiones programadas que hiciste (`nil` sin sesiones pasadas).
    public var planAdherence: Double? { planned > 0 ? score / Double(planned) : nil }
    /// Días con carrera en la ventana (dentro y fuera del plan).
    public var runDays: Int = 0
    /// Sesiones de carrera programadas en los días ya transcurridos, incluidas
    /// las excusadas por enfermedad o lesión (que no cuentan).
    public var scheduledInWindow: Int = 0

    /// Frecuencia real frente a la programada **en los días transcurridos**
    /// (máx. 1): días con carrera ÷ sesiones programadas hasta ayer, sin las
    /// excusadas. Así una semana a medias no se compara con una semana entera
    /// (antes de 0.10.0 (106): carreras de la ventana ÷ objetivo semanal, sin
    /// normalizar cuando la ventana era de menos de 7 días). Sin sesiones
    /// programadas, se compara con el objetivo semanal por semana transcurrida.
    public var frequencyRatio: Double {
        let expected = scheduledInWindow - excused
        if expected > 0 { return min(Double(runDays) / Double(expected), 1) }
        return targetRunsPerWeek > 0 ? min(actualRunsPerWeek / Double(targetRunsPerWeek), 1) : 1
    }
    /// El menor entre adherencia y frecuencia, tal como se observa.
    public var effective: Double? { planAdherence.map { min($0, frequencyRatio) } }
    /// Menos de 2 semanas o menos de 4 sesiones: dato todavía limitado.
    public var isLimited: Bool { windowWeeks < 2 || planned < 4 }

    /// Sesiones equivalentes del supuesto con el que se mezcla un dato limitado.
    public static let priorSessions = 4.0

    /// Cumplimiento para la proyección. Con pocos datos (`isLimited`) se acerca
    /// al supuesto del escenario central (85 %) según cuántas sesiones hay:
    /// (n × observado + 4 × 0,85) ÷ (n + 4). Con 4 sesiones pesan igual el
    /// observado y el supuesto; con más, manda lo observado. Sin sesiones: `nil`
    /// (se usa el supuesto de cada escenario).
    public var projectionCompliance: Double? {
        guard let observed = effective else { return nil }
        guard isLimited else { return observed }
        let n = Double(planned)
        let prior = GoalProjection.Scenario.central.assumedCompliance
        return (n * observed + Self.priorSessions * prior) / (n + Self.priorSessions)
    }

    public static let windowDays = 28

    /// - `skips`: motivo por día de sesión (inicio del día).
    /// - `healthDays`: días con un evento de salud que impide entrenar
    ///   (enfermedad, fiebre, lesión): sus sesiones no hechas no cuentan.
    public static func evaluate(plan: TrainingPlan, runs: [WorkoutSummary], today: Date, calendar: Calendar, skips: [Date: SessionSkipReason] = [:], healthDays: Set<Date> = []) -> TrainingAdherence {
        let todayStart = calendar.startOfDay(for: today)
        let planStart = plan.weeks.first.map { calendar.startOfDay(for: $0.start) } ?? todayStart
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) ?? todayStart
        let windowStart = max(planStart, fourWeeksAgo)
        let days = max(calendar.dateComponents([.day], from: windowStart, to: todayStart).day ?? 0, 0)
        let sessions = plan.weeks.flatMap(\.sessions).filter { $0.date >= windowStart && calendar.startOfDay(for: $0.date) < todayStart }
        let allRunning = sessions.filter { $0.kind != .rest }
        var running: [PlannedSession] = []
        var score = 0.0
        var done = 0, partial = 0, missed = 0, excused = 0
        var reasons: [SessionSkipReason: Int] = [:]
        for session in allRunning {
            let day = calendar.startOfDay(for: session.date)
            switch SessionCompletion.evaluate(session, runs: runs, today: today, calendar: calendar) {
            case .done:
                score += 1
                done += 1
                running.append(session)
            case let .partial(distance):
                score += session.distance > 0 ? min(distance / session.distance, 0.8) : 0.5
                partial += 1
                running.append(session)
            default:
                let reason = skips[day]
                if let reason { reasons[reason, default: 0] += 1 }
                if reason?.isExcused == true || (reason == nil && healthDays.contains(day)) {
                    excused += 1
                } else {
                    missed += 1
                    running.append(session)
                }
            }
        }
        // Días con carrera (una carrera partida en varios registros cuenta una vez).
        let windowRuns = runs.filter { $0.activity.isRun && $0.start >= windowStart && $0.start < todayStart && ($0.distanceMeters ?? 0) >= 1000 }
        let runningDays = Set(windowRuns.map { calendar.startOfDay(for: $0.start) })
        let planDays = Set(allRunning.map { calendar.startOfDay(for: $0.date) })
        let outside = runningDays.subtracting(planDays).count
        let weeks = Double(days) / 7
        let started = plan.weeks.filter { $0.start <= today }.count
        var result = TrainingAdherence(
            planned: running.count,
            done: done,
            score: score,
            targetRunsPerWeek: plan.goal.runsPerWeek,
            actualRunsPerWeek: weeks >= 1 ? Double(runningDays.count) / weeks : Double(runningDays.count),
            windowWeeks: weeks,
            weeksWithPlan: started,
            runsOutsidePlan: outside
        )
        result.partial = partial
        result.missed = missed
        result.excused = excused
        result.skipReasons = reasons
        result.runDays = runningDays.count
        result.scheduledInWindow = allRunning.count
        return result
    }
}

/// Proyección de la forma hasta una fecha: una distribución predictiva.
///
/// Reglas (RUNNING_ENGINE.md, "Proyección", versión 1.6):
/// - **Tasa de adaptación** r ~ N(media, σ²) de `IndividualAdaptationModel`:
///   la referencia (1/6 VDOT/semana × factor de cumplimiento × frecuencia)
///   combinada con tu tendencia observada según la información que haya.
/// - **Rendimientos decrecientes**, simétricos: mejora = signo(r) × 4 × (1 −
///   e^(−semanas × |r| / 4)). Casi lineal al principio, se aplana; también un
///   deterioro se acota. Es un supuesto de HÅLSYN, no una ley.
/// - **Factor de cumplimiento**: rampa continua (c − 40 %) ÷ 60 % entre 0 y 1
///   (sin corte en 90 %). Sin datos: 85 %.
/// - **Incertidumbre de adherencia**: con n sesiones, sd(c) = √(c(1−c)/(n+5));
///   pocas sesiones no dan una confianza desproporcionada.
/// - **Frecuencia** (simulador): 1 día/semana 0,4; 2 → 0,6; 3 → 0,85; 4 o más → 1.
/// - **Varianza total** = forma hoy² + (∂mejora/∂r)² × (σ_r² + σ_adherencia²) +
///   (0,15 × √semanas)² + 0,7² (día de la carrera).
/// - **Escenarios**: percentiles 10, 50 y 90 de esa distribución (±1,2816 σ).
///   Orientativos: no están calibrados hasta comprobar su cobertura.
public enum GoalProjection {
    public enum Scenario: Int, CaseIterable, Hashable, Sendable {
        case conservative, central, optimistic

        /// Cuantil normal del escenario (P10, P50, P90).
        public var quantile: Double {
            switch self {
            case .conservative: -1.2816
            case .central: 0
            case .optimistic: 1.2816
            }
        }

        /// Percentil que representa.
        public var percentile: Int {
            switch self {
            case .conservative: 10
            case .central: 50
            case .optimistic: 90
            }
        }

        /// Cumplimiento supuesto sin datos (el mismo para los tres: la
        /// diferencia entre escenarios sale de la incertidumbre, no de supuestos distintos).
        public var assumedCompliance: Double { 0.85 }
    }

    public struct Result: Hashable, Sendable {
        public let scenario: Scenario
        public let weeks: Int
        /// Tasa media usada (VDOT/semana).
        public let rate: Double
        public let complianceFactor: Double
        public let frequencyFactor: Double
        /// Mejora de este escenario (VDOT; puede ser negativa).
        public let gain: Double
        public let projectedVDOT: Double
        /// Desviación de la distribución predictiva (VDOT).
        public let uncertainty: Double
        public let usesPersonalTrend: Bool
        /// Estado y desglose de la adaptación individual.
        public var adaptation: AdaptationEstimate?
        /// Componentes de la varianza (VDOT²): forma hoy, tasa, adherencia, horizonte, día de la carrera.
        public var varianceParts: [String: Double] = [:]
        /// Media de la distribución (escenario central).
        public var meanVDOT: Double = 0
    }

    public static let improvementCap = 4.0
    public static let horizonUncertaintyPerRootWeek = 0.15
    public static let raceDayUncertainty = 0.7
    public static let priorComplianceSessions = 5.0

    public static func frequencyFactor(runsPerWeek: Int) -> Double {
        switch runsPerWeek {
        case ..<1: 0
        case 1: 0.4
        case 2: 0.6
        case 3: 0.85
        default: 1
        }
    }

    /// Mejora acotada y simétrica para una tasa (positiva o negativa).
    public static func gain(weeks: Int, rate: Double) -> Double {
        guard weeks > 0, rate != 0 else { return 0 }
        let magnitude = improvementCap * (1 - exp(-Double(weeks) * abs(rate) / improvementCap))
        return rate > 0 ? magnitude : -magnitude
    }

    /// Compatibilidad: mejora con tasa × factor (factor ≤ 0 → 0).
    public static func gain(weeks: Int, rate: Double, factor: Double) -> Double {
        guard factor > 0 else { return 0 }
        return gain(weeks: weeks, rate: rate * factor)
    }

    /// Derivada de la mejora respecto de la tasa (para propagar la incertidumbre).
    static func gainSlope(weeks: Int, rate: Double) -> Double {
        guard weeks > 0 else { return 0 }
        return Double(weeks) * exp(-Double(weeks) * abs(rate) / improvementCap)
    }

    /// - `complianceSessions`: sesiones en que se basa `compliance` (para su incertidumbre).
    public static func project(performance: PerformanceAssessment, weeks: Int, compliance: Double?, runsPerWeek: Int, scenario: Scenario, complianceSessions: Int? = nil, today: Date = .now, calendar: Calendar = .current) -> Result {
        let used = compliance ?? scenario.assumedCompliance
        let complianceFactor = GoalProbability.gainFactor(used)
        let frequency = frequencyFactor(runsPerWeek: runsPerWeek)
        let referenceRate = IndividualAdaptationModel.baseRate * complianceFactor * frequency
        let adaptation = IndividualAdaptationModel.estimate(evidence: performance.evidence, referenceRate: referenceRate, today: today, calendar: calendar)
        let rate = adaptation.rate

        // Incertidumbre de la adherencia: solo afecta a la parte de referencia.
        let sessions = Double(complianceSessions ?? 0)
        let complianceSD = compliance == nil ? 0.15 : (used * (1 - used) / (sessions + priorComplianceSessions)).squareRoot()
        let factorSD = used > 0.4 && used < 1 ? complianceSD / 0.6 : 0
        let adherenceRateSD = IndividualAdaptationModel.baseRate * frequency * factorSD * adaptation.referenceWeight

        let slope = gainSlope(weeks: weeks, rate: rate)
        let parts: [String: Double] = [
            "current": performance.uncertainty * performance.uncertainty,
            "rate": pow(slope * adaptation.rateSD, 2),
            "adherence": pow(slope * adherenceRateSD, 2),
            "horizon": pow(horizonUncertaintyPerRootWeek * Double(max(weeks, 0)).squareRoot(), 2),
            "raceDay": raceDayUncertainty * raceDayUncertainty,
        ]
        let sigma = parts.values.reduce(0, +).squareRoot()
        let meanGain = gain(weeks: weeks, rate: rate)
        let mean = performance.currentVDOT + meanGain
        let projected = mean + scenario.quantile * sigma
        var result = Result(scenario: scenario, weeks: weeks, rate: rate, complianceFactor: complianceFactor, frequencyFactor: frequency, gain: projected - performance.currentVDOT, projectedVDOT: projected, uncertainty: sigma, usesPersonalTrend: adaptation.state != .reference)
        result.adaptation = adaptation
        result.varianceParts = parts
        result.meanVDOT = mean
        return result
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
        let scenarios = wanted.map { GoalProjection.project(performance: performance, weeks: weeks, compliance: compliance, runsPerWeek: runsPerWeek, scenario: $0, today: today, calendar: calendar) }
        guard let central = scenarios.first(where: { $0.scenario == .central }) else { return nil }
        let z = (central.projectedVDOT - goalVDOT) / central.uncertainty
        let category: GoalProbability.Category = z >= 1 ? .veryLikely : (z >= 0 ? .achievable : (z >= -1 ? .demanding : .unrealistic))
        return GoalSimulation(distance: distance.rawValue, goalTime: goalTime, raceDate: raceDate, runsPerWeek: runsPerWeek, weeks: weeks, currentTime: VDOT.raceTime(vdot: performance.currentVDOT, distance: distance.rawValue), scenarios: scenarios, category: category)
    }
}
