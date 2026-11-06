import Foundation

/// Probabilidad de llegar al tiempo objetivo del plan el día de la carrera.
///
/// Cómo se calcula (se recalcula cada vez con los datos nuevos):
///
/// 1. **Forma de hoy**: el VDOT de `FitnessEstimator`. Sale de tu último test
///    o carrera, o del mejor esfuerzo de 3 km o más de las últimas 6 semanas,
///    **esté o no en el plan**: así cuentan tus ritmos actuales.
/// 2. **Mejora esperada**: la pauta prudente de Daniels (1 punto de VDOT cada
///    6 semanas de entrenamiento constante) por las semanas que quedan antes
///    del afinamiento, multiplicada por cuánto estás cumpliendo el plan.
/// 3. **Cumplimiento**: las sesiones de carrera de las últimas 4 semanas del
///    plan (hechas = 1; en parte = la fracción corrida, como mucho 0,8; no
///    hechas = 0). Con el 90 % o más cuenta la mejora entera; con el 40 % o
///    menos, ninguna. Sin sesiones pasadas se asume un 85 % (lo típico) y se
///    suma incertidumbre.
/// 4. **Incertidumbre** (desviación en puntos de VDOT), sumando:
///    - la forma de hoy: 1 punto con un test reciente; hasta 2 si el test es
///      viejo; 2 si sale de entrenamientos (que casi nunca son a tope);
///    - la mejora: la mitad de la mejora esperada (varía mucho entre personas);
///    - el día de la carrera (clima, recorrido, cómo amaneces): 0,7 puntos.
/// 5. Probabilidad = P(forma el día de la carrera ≥ forma que pide el
///    objetivo), con una distribución normal. Se acota entre 3 % y 97 %:
///    nunca hay certeza.
///
/// No es optimista ni pesimista a propósito: el centro es la proyección y la
/// incertidumbre es simétrica. Las cifras de incertidumbre son una elección
/// de HÅLSYN para que el número sea razonable, no salen de un estudio.
public struct GoalProbability: Hashable, Sendable {
    public enum Level: String, Hashable, Sendable {
        /// 70 % o más.
        case likely
        /// Entre 40 y 70 %.
        case possible
        /// Menos del 40 %.
        case unlikely
    }

    /// 0,03…0,97.
    public let value: Double
    public let goalVDOT: Double
    public let currentVDOT: Double
    /// Forma prevista el día de la carrera.
    public let projectedVDOT: Double
    public let projectedTime: TimeInterval
    /// Mejora esperada hasta la carrera (puntos de VDOT).
    public let expectedGain: Double
    /// Fracción de las sesiones recientes cumplidas, si ya hay sesiones pasadas.
    public let compliance: Double?
    public let sessionsDone: Int
    public let sessionsPlanned: Int
    public let trainingWeeks: Int
    /// Desviación total en puntos de VDOT.
    public let uncertainty: Double

    public var level: Level {
        if value >= 0.7 { return .likely }
        if value >= 0.4 { return .possible }
        return .unlikely
    }

    /// Porcentaje entero (3…97).
    public var percent: Int { Int((value * 100).rounded()) }

    public static let minimum = 0.03
    public static let maximum = 0.97
    public static let complianceWindowDays = 28
    public static let assumedCompliance = 0.85
    public static let raceDayUncertainty = 0.7

    /// `nil` sin tiempo objetivo, sin estimación de forma o con la carrera ya pasada.
    public static func evaluate(plan: TrainingPlan, estimate: FitnessEstimate?, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> GoalProbability? {
        guard let goalTime = plan.goal.goalTime,
              let goalVDOT = VDOT.value(distance: plan.goal.distance.rawValue, time: goalTime),
              let estimate,
              calendar.startOfDay(for: today) <= calendar.startOfDay(for: plan.goal.raceDate)
        else { return nil }

        let weeks = GoalCoach.trainingWeeks(until: plan.goal.raceDate, distance: plan.goal.distance, today: today, calendar: calendar)
        let record = complianceRecord(plan: plan, runs: runs, today: today, calendar: calendar)
        let compliance = record.planned > 0 ? record.score / Double(record.planned) : nil
        let factor = gainFactor(compliance ?? assumedCompliance)
        let fullGain = Double(weeks) / GoalCoach.realisticWeeksPerPoint
        let gain = fullGain * factor
        let projected = estimate.vdot + gain

        let fitnessSigma = fitnessUncertainty(estimate, today: today, calendar: calendar)
        var gainSigma = gain * 0.5
        if compliance == nil { gainSigma += 0.3 }
        let sigma = (fitnessSigma * fitnessSigma + gainSigma * gainSigma + raceDayUncertainty * raceDayUncertainty).squareRoot()

        let z = (projected - goalVDOT) / sigma
        let probability = min(max(normalCDF(z), minimum), maximum)
        return GoalProbability(
            value: probability,
            goalVDOT: goalVDOT,
            currentVDOT: estimate.vdot,
            projectedVDOT: projected,
            projectedTime: VDOT.raceTime(vdot: projected, distance: plan.goal.distance.rawValue),
            expectedGain: gain,
            compliance: compliance,
            sessionsDone: record.done,
            sessionsPlanned: record.planned,
            trainingWeeks: weeks,
            uncertainty: sigma
        )
    }

    /// Qué parte de la mejora habitual cuenta según el cumplimiento.
    public static func gainFactor(_ compliance: Double) -> Double {
        min(max((compliance - 0.4) / 0.5, 0), 1)
    }

    static func fitnessUncertainty(_ estimate: FitnessEstimate, today: Date, calendar: Calendar) -> Double {
        if estimate.isFromTraining { return 2 }
        let age = Double(estimate.ageInDays(today: today, calendar: calendar))
        let fresh = Double(FitnessEstimator.freshDays)
        guard age > fresh else { return 1 }
        return min(1 + 0.5 * (age - fresh) / fresh, 2)
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
