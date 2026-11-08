import Foundation

/// Qué tan factible es el objetivo del plan el día de la carrera.
///
/// Se muestra como **categoría** con el tiempo previsto y su rango, no como un
/// porcentaje: un porcentaje solo sería defendible si estuviera calibrado con
/// resultados reales, y eso aún no existe (`isCalibrated`). El valor
/// numérico del modelo (`modelValue`) se conserva para la evaluación
/// retrospectiva.
///
/// Cálculo (RUNNING_ENGINE.md, "Factibilidad del objetivo"):
/// 1. **Forma de hoy** y su incertidumbre: `RacePerformanceModel` (varias pruebas
///    ponderadas, tendencia robusta, coherencia entre pruebas).
/// 2. **Mejora esperada** hasta el afinamiento: mitad pauta prudente de
///    Daniels (1 punto de VDOT cada 6 semanas) y mitad tu tendencia observada
///    (si la hay, entre 0 y +0,25 por semana), multiplicada por el
///    cumplimiento del plan de las últimas 4 semanas (≥ 90 % cuenta entera,
///    ≤ 40 % nada; sin sesiones pasadas se asume 85 %).
/// 3. **Incertidumbre total**: la del modelo, la mitad de la mejora esperada
///    (varía mucho entre personas) y 0,7 puntos por el día de la carrera.
/// 4. **Categoría** según z = (forma prevista − forma que pide el objetivo) /
///    incertidumbre: z ≥ 1 muy probable; 0…1 alcanzable; −1…0 exigente;
///    < −1 poco realista por ahora. Con el objetivo justo en lo previsto,
///    "alcanzable" en el límite con "exigente": ni optimista ni pesimista.
public struct GoalProbability: Hashable, Sendable {
    public enum Category: Int, Comparable, Hashable, Sendable {
        case unrealistic, demanding, achievable, veryLikely
        public static func < (lhs: Category, rhs: Category) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Factor que acerca o aleja el objetivo, con el dato que lo justifica.
    public struct Factor: Hashable, Identifiable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            /// Puntos de VDOT entre tu forma de hoy y la que pide el objetivo.
            case gap
            /// Sesiones cumplidas en las últimas 4 semanas (fracción).
            case compliance
            /// Tendencia de tu forma (VDOT por semana).
            case trend
            /// Semanas que quedan frente a las recomendadas para la distancia.
            case time
            /// Kilómetros por semana (últimas 4) frente a los recomendados.
            case volume
            /// Confianza de la estimación de la forma.
            case confidence
        }

        public enum Effect: Int, Hashable, Sendable {
            case hinders, neutral, favors
        }

        public let kind: Kind
        public let effect: Effect
        /// Valor principal (unidad según `kind`).
        public let value: Double
        /// Valor de referencia (lo recomendado o necesario), si aplica.
        public let reference: Double?

        public var id: Kind { kind }
    }

    public let category: Category
    /// Probabilidad del modelo sin calibrar (0…1). No se muestra como porcentaje.
    public let modelValue: Double
    /// `false` hasta que haya resultados reales con los que calibrar.
    public let isCalibrated: Bool
    public let goalVDOT: Double
    public let currentVDOT: Double
    public let projectedVDOT: Double
    public let projectedTime: TimeInterval
    /// Rango del 80 % del tiempo previsto el día de la carrera.
    public let projectedRange: ClosedRange<TimeInterval>
    public let expectedGain: Double
    public let compliance: Double?
    public let sessionsDone: Int
    public let sessionsPlanned: Int
    public let trainingWeeks: Int
    public let uncertainty: Double
    public let confidence: PerformanceAssessment.Confidence
    public let factors: [Factor]
    /// A. Rendimiento actual: tiempo para la distancia del objetivo hoy.
    public var currentTime: TimeInterval = 0
    /// Rango orientativo del tiempo de hoy (±1,28 σ de la forma actual).
    public var currentRange: ClosedRange<TimeInterval>?
    /// Segundos por km que te faltan hoy para el objetivo (negativo = ya lo tienes).
    public var requiredPaceChange: Double = 0
    /// Adherencia y frecuencia, separadas.
    public var adherence: TrainingAdherence?
    /// Escenarios con supuestos explícitos (con confianza media o alta).
    public var scenarios: [GoalProjection.Result] = []
    /// El escenario central con todos sus términos (para explicar la cuenta).
    public var central: GoalProjection.Result?

    public static let complianceWindowDays = 28
    public static let assumedCompliance = 0.85
    public static let raceDayUncertainty = 0.7

    /// `nil` sin tiempo objetivo, sin estimación de forma o con la carrera ya pasada.
    public static func evaluate(plan: TrainingPlan, performance: PerformanceAssessment?, runs: [WorkoutSummary], today: Date, calendar: Calendar, skips: [Date: SessionSkipReason] = [:], healthDays: Set<Date> = []) -> GoalProbability? {
        guard let goalTime = plan.goal.goalTime,
              let goalVDOT = VDOT.value(distance: plan.goal.distance.rawValue, time: goalTime),
              let performance,
              calendar.startOfDay(for: today) <= calendar.startOfDay(for: plan.goal.raceDate)
        else { return nil }

        let weeks = GoalCoach.trainingWeeks(until: plan.goal.raceDate, distance: plan.goal.distance, today: today, calendar: calendar)
        let adherence = TrainingAdherence.evaluate(plan: plan, runs: runs, today: today, calendar: calendar, skips: skips, healthDays: healthDays)
        let record = (score: adherence.score, done: adherence.done, planned: adherence.planned)
        let compliance = adherence.effective
        let central = GoalProjection.project(performance: performance, weeks: weeks, compliance: compliance, runsPerWeek: plan.goal.runsPerWeek, scenario: .central)
        let gain = central.gain
        let projected = central.projectedVDOT
        let sigma = central.uncertainty
        let z = (projected - goalVDOT) / sigma
        let category: Category = z >= 1 ? .veryLikely : (z >= 0 ? .achievable : (z >= -1 ? .demanding : .unrealistic))

        let distance = plan.goal.distance.rawValue
        let fast = VDOT.raceTime(vdot: projected + 1.28 * sigma, distance: distance)
        let slow = VDOT.raceTime(vdot: max(projected - 1.28 * sigma, 15), distance: distance)
        let currentTime = VDOT.raceTime(vdot: performance.currentVDOT, distance: distance)
        let currentRange = performance.hasInterval
            ? VDOT.raceTime(vdot: performance.currentVDOT + 1.28 * performance.uncertainty, distance: distance)...VDOT.raceTime(vdot: max(performance.currentVDOT - 1.28 * performance.uncertainty, 15), distance: distance)
            : nil
        let scenarios = performance.confidence >= .medium
            ? GoalProjection.Scenario.allCases.map { GoalProjection.project(performance: performance, weeks: weeks, compliance: compliance, runsPerWeek: plan.goal.runsPerWeek, scenario: $0) }
            : []
        let ruleRate = 1 / GoalCoach.realisticWeeksPerPoint

        // Factores, con sus umbrales documentados.
        var factors: [Factor] = []
        let needed = goalVDOT - performance.currentVDOT
        let fullGain = GoalProjection.gain(weeks: weeks, rate: ruleRate, factor: 1)
        factors.append(Factor(kind: .gap, effect: needed <= 0 ? .favors : (needed <= fullGain ? .neutral : .hinders), value: needed, reference: fullGain))
        if let compliance {
            factors.append(Factor(kind: .compliance, effect: compliance >= 0.85 ? .favors : (compliance >= 0.6 ? .neutral : .hinders), value: compliance, reference: 0.85))
        }
        if let trend = performance.weeklyTrend {
            factors.append(Factor(kind: .trend, effect: trend >= 0.05 ? .favors : (trend <= -0.05 ? .hinders : .neutral), value: trend, reference: nil))
        }
        let totalWeeks = (calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: plan.goal.raceDate)).day ?? 0) / 7
        let minimumWeeks = GoalCoach.minimumWeeks(plan.goal.distance)
        factors.append(Factor(kind: .time, effect: totalWeeks >= minimumWeeks ? .favors : .hinders, value: Double(totalWeeks), reference: Double(minimumWeeks)))
        let weekly = weeklyDistance(runs: runs, today: today, calendar: calendar)
        let minimumVolume = GoalCoach.minimumWeeklyDistance(plan.goal.distance)
        factors.append(Factor(kind: .volume, effect: weekly >= minimumVolume ? .favors : (weekly >= minimumVolume * 0.7 ? .neutral : .hinders), value: weekly, reference: minimumVolume))
        factors.append(Factor(kind: .confidence, effect: performance.confidence == .high ? .favors : (performance.confidence == .medium ? .neutral : .hinders), value: Double(performance.confidence.rawValue), reference: nil))

        return GoalProbability(
            category: category,
            modelValue: normalCDF(z),
            isCalibrated: false,
            goalVDOT: goalVDOT,
            currentVDOT: performance.currentVDOT,
            projectedVDOT: projected,
            projectedTime: VDOT.raceTime(vdot: projected, distance: distance),
            projectedRange: fast...slow,
            expectedGain: gain,
            compliance: compliance,
            sessionsDone: record.done,
            sessionsPlanned: record.planned,
            trainingWeeks: weeks,
            uncertainty: sigma,
            confidence: performance.confidence,
            factors: factors,
            currentTime: currentTime,
            currentRange: currentRange,
            requiredPaceChange: (currentTime - goalTime) / (distance / 1000),
            adherence: adherence,
            scenarios: scenarios,
            central: central
        )
    }

    /// Qué parte de la mejora esperada cuenta según el cumplimiento.
    public static func gainFactor(_ compliance: Double) -> Double {
        min(max((compliance - 0.4) / 0.5, 0), 1)
    }

    /// Kilómetros por semana (media de los últimos 28 días), en metros.
    static func weeklyDistance(runs: [WorkoutSummary], today: Date, calendar: Calendar) -> Double {
        let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: today)) ?? today
        let total = runs.filter { $0.activity.isRun && $0.start >= start && $0.start <= today }.compactMap(\.distanceMeters).reduce(0, +)
        return total / 4
    }

    /// Sesiones de carrera de las últimas 4 semanas del plan, hasta ayer.
    static func complianceRecord(plan: TrainingPlan, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> (score: Double, done: Int, planned: Int) {
        let todayStart = calendar.startOfDay(for: today)
        let windowStart = calendar.date(byAdding: .day, value: -complianceWindowDays, to: todayStart) ?? todayStart
        let sessions = plan.weeks.flatMap(\.sessions).filter { session in
            session.kind != .rest && session.date >= windowStart && calendar.startOfDay(for: session.date) < todayStart
        }
        var score = 0.0
        var done = 0
        for session in sessions {
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
        return (score, done, sessions.count)
    }

    /// Función de distribución de la normal estándar.
    static func normalCDF(_ z: Double) -> Double {
        0.5 * erfc(-z / 2.0.squareRoot())
    }
}
