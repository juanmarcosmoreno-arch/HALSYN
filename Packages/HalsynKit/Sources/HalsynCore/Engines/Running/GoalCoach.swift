import Foundation

/// Un esfuerzo a tope con tiempo conocido: un test o una carrera.
public struct PerformanceResult: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case test
        case race
    }

    public var id: UUID
    public var date: Date
    /// Metros.
    public var distance: Double
    /// Segundos.
    public var time: TimeInterval
    public var kind: Kind
    /// Entrenamiento de Salud del que sale, si se detectó solo.
    public var workoutID: UUID?

    public init(id: UUID = UUID(), date: Date, distance: Double, time: TimeInterval, kind: Kind, workoutID: UUID? = nil) {
        self.id = id
        self.date = date
        self.distance = distance
        self.time = time
        self.kind = kind
        self.workoutID = workoutID
    }

    public var vdot: Double? { VDOT.value(distance: distance, time: time) }
}

/// Tu forma actual expresada como VDOT, con su origen.
public struct FitnessEstimate: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// Un test o una carrera registrados.
        case result(PerformanceResult)
        /// El mejor esfuerzo entre tus entrenamientos recientes: probablemente
        /// se queda corto, porque casi nunca se entrena a tope.
        case training(runs: Int)
    }

    public let vdot: Double
    public let date: Date
    public let source: Source

    public init(vdot: Double, date: Date, source: Source) {
        self.vdot = vdot
        self.date = date
        self.source = source
    }

    public var isFromTraining: Bool {
        if case .training = source { return true }
        return false
    }

    public func ageInDays(today: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: today)).day ?? 0
    }

    /// Conviene un test: el dato sale de entrenamientos o tiene más de 6 semanas.
    public func needsTest(today: Date, calendar: Calendar) -> Bool {
        isFromTraining || ageInDays(today: today, calendar: calendar) > FitnessEstimator.freshDays
    }
}

/// Elige la mejor estimación de tu forma.
///
/// 1. Un test o carrera de las últimas 6 semanas (lo más fiable).
/// 2. Si no, el mayor VDOT entre un resultado más antiguo (hasta 4 meses) y
///    tus entrenamientos de 3 km o más de las últimas 6 semanas.
/// 3. Sin nada de eso, no hay estimación: hace falta un test.
public enum FitnessEstimator {
    public static let freshDays = 42
    public static let maximumResultAgeDays = 120
    public static let trainingWindowDays = 42
    public static let minimumRunDistance: Double = 3000

    public static func estimate(results: [PerformanceResult], runs: [WorkoutSummary], today: Date, calendar: Calendar) -> FitnessEstimate? {
        let todayStart = calendar.startOfDay(for: today)
        func age(_ date: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: todayStart).day ?? .max }

        let valid = results
            .filter { $0.date <= today && age($0.date) <= maximumResultAgeDays && $0.vdot != nil }
            .sorted { $0.date > $1.date }
        if let latest = valid.first, age(latest.date) <= freshDays, let vdot = latest.vdot {
            return FitnessEstimate(vdot: vdot, date: latest.date, source: .result(latest))
        }

        let windowStart = calendar.date(byAdding: .day, value: -trainingWindowDays, to: todayStart) ?? todayStart
        let recent = runs.filter { $0.activity.isRun && $0.start >= windowStart && $0.start <= today && ($0.distanceMeters ?? 0) >= minimumRunDistance }
        let best = recent.compactMap { run -> (Double, Date)? in
            guard let distance = run.distanceMeters, let vdot = VDOT.value(distance: distance, time: run.duration) else { return nil }
            return (vdot, run.start)
        }.max { $0.0 < $1.0 }

        let older = valid.first.flatMap { result in result.vdot.map { (result, $0) } }
        switch (older, best) {
        case let ((result, resultVDOT)?, (trainingVDOT, _)?) where resultVDOT >= trainingVDOT:
            return FitnessEstimate(vdot: resultVDOT, date: result.date, source: .result(result))
        case let (_, (trainingVDOT, date)?):
            return FitnessEstimate(vdot: trainingVDOT, date: date, source: .training(runs: recent.count))
        case let ((result, resultVDOT)?, nil):
            return FitnessEstimate(vdot: resultVDOT, date: result.date, source: .result(result))
        case (nil, nil):
            return nil
        }
    }
}

/// ¿Es posible el objetivo?
public struct GoalAssessment: Hashable, Sendable {
    public enum Verdict: String, Hashable, Sendable {
        /// Tu forma actual ya da el tiempo objetivo.
        case alreadyThere
        /// Pide una mejora dentro de lo habitual para el tiempo disponible.
        case realistic
        /// Pide mejorar más rápido de lo habitual.
        case ambitious
        /// Pide más del doble de la mejora habitual.
        case unlikely
    }

    public enum Warning: Hashable, Sendable {
        /// Menos semanas de las que se suelen recomendar para esa distancia.
        case shortPreparation(minimumWeeks: Int)
        /// Volumen actual bajo para empezar a preparar esa distancia (metros).
        case lowVolume(minimumWeekly: Double)
        /// La forma sale de entrenamientos: conviene un test.
        case estimateFromTraining
        /// El último test o carrera tiene más de 6 semanas.
        case staleEstimate
    }

    public let distance: RaceDistance
    public let currentVDOT: Double
    /// Tiempo previsto hoy, con tu forma actual.
    public let predictedTime: TimeInterval
    /// Tiempo con la mejora habitual hasta la carrera.
    public let reachableTime: TimeInterval
    public let goalTime: TimeInterval?
    public let goalVDOT: Double?
    public let verdict: Verdict?
    /// Semanas de entrenamiento antes del afinamiento.
    public let trainingWeeks: Int
    public let warnings: [Warning]
}

/// Viabilidad y seguimiento de un objetivo de carrera.
///
/// - La mejora "habitual" sigue la regla práctica de Daniels: subir como
///   mucho 1 punto de VDOT cada 4–6 semanas de entrenamiento constante. Se usa
///   el extremo prudente (6 semanas). Es una pauta de entrenadores, no un
///   resultado de estudios: la mejora real varía mucho entre personas.
/// - "Ambicioso": hasta el doble de esa velocidad (1 punto cada 3 semanas).
/// - Semanas mínimas y volumen de partida por distancia: pautas habituales
///   de planes de entrenamiento, orientativas.
public enum GoalCoach {
    public static let realisticWeeksPerPoint = 6.0
    public static let ambitiousWeeksPerPoint = 3.0

    public static func minimumWeeks(_ distance: RaceDistance) -> Int {
        switch distance {
        case .fiveK: 6
        case .tenK: 8
        case .half: 10
        case .marathon: 16
        }
    }

    /// Volumen semanal con el que conviene empezar a preparar la distancia (m).
    public static func minimumWeeklyDistance(_ distance: RaceDistance) -> Double {
        switch distance {
        case .fiveK: 8000
        case .tenK: 12_000
        case .half: 20_000
        case .marathon: 30_000
        }
    }

    public static func trainingWeeks(until raceDate: Date, distance: RaceDistance, today: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: raceDate)).day ?? 0
        return max(0, days / 7 - TrainingPlanGenerator.taperWeeks(distance))
    }

    public static func assess(goalTime: TimeInterval?, distance: RaceDistance, raceDate: Date, estimate: FitnessEstimate, weeklyDistance: Double, today: Date, calendar: Calendar) -> GoalAssessment {
        let weeks = trainingWeeks(until: raceDate, distance: distance, today: today, calendar: calendar)
        let predicted = VDOT.raceTime(vdot: estimate.vdot, distance: distance.rawValue)
        let reachable = VDOT.raceTime(vdot: estimate.vdot + Double(weeks) / realisticWeeksPerPoint, distance: distance.rawValue)

        var verdict: GoalAssessment.Verdict?
        let goalVDOT = goalTime.flatMap { VDOT.value(distance: distance.rawValue, time: $0) }
        if let goalVDOT {
            let needed = goalVDOT - estimate.vdot
            if needed <= 0 {
                verdict = .alreadyThere
            } else if needed <= Double(weeks) / realisticWeeksPerPoint {
                verdict = .realistic
            } else if needed <= Double(weeks) / ambitiousWeeksPerPoint {
                verdict = .ambitious
            } else {
                verdict = .unlikely
            }
        }

        var warnings: [GoalAssessment.Warning] = []
        let totalWeeks = (calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: raceDate)).day ?? 0) / 7
        if totalWeeks < minimumWeeks(distance) { warnings.append(.shortPreparation(minimumWeeks: minimumWeeks(distance))) }
        if weeklyDistance < minimumWeeklyDistance(distance) { warnings.append(.lowVolume(minimumWeekly: minimumWeeklyDistance(distance))) }
        if estimate.isFromTraining {
            warnings.append(.estimateFromTraining)
        } else if estimate.ageInDays(today: today, calendar: calendar) > FitnessEstimator.freshDays {
            warnings.append(.staleEstimate)
        }

        return GoalAssessment(distance: distance, currentVDOT: estimate.vdot, predictedTime: predicted, reachableTime: reachable, goalTime: goalTime, goalVDOT: goalVDOT, verdict: verdict, trainingWeeks: weeks, warnings: warnings)
    }

    /// Entrenamiento que parece el test de esa sesión: el mismo día o el
    /// siguiente, con una distancia de entre el 97 y el 120 por ciento de la del test.
    public static func testCandidate(for session: PlannedSession, runs: [WorkoutSummary], calendar: Calendar) -> WorkoutSummary? {
        guard session.kind == .test, let target = session.repeatDistance else { return nil }
        let day = calendar.startOfDay(for: session.date)
        let end = calendar.date(byAdding: .day, value: 2, to: day) ?? day
        return runs
            .filter { $0.activity.isRun && $0.start >= day && $0.start < end }
            .filter { run in (run.distanceMeters ?? 0) >= target * 0.97 && (run.distanceMeters ?? 0) <= target * 1.2 }
            .min { abs(($0.distanceMeters ?? 0) - target) < abs(($1.distanceMeters ?? 0) - target) }
    }
}

/// ¿Vas bien? Kilómetros hechos frente a los planeados en las últimas
/// semanas completas, y tu forma frente a la del inicio del plan.
public struct PlanProgress: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        /// Aún no hay ninguna semana completa del plan.
        case notStarted
        case onTrack
        case slightlyBehind
        case behind
        /// Más de un 20 por ciento por encima de lo planeado.
        case abovePlan
    }

    public let status: Status
    public let plannedDistance: Double
    public let actualDistance: Double
    public let weeksEvaluated: Int
    /// Cambio de VDOT desde el inicio del plan, si hay una estimación nueva.
    public let vdotChange: Double?
    /// Tiempo previsto el día de la carrera: forma actual más la mejora
    /// habitual en las semanas que quedan.
    public let projectedTime: TimeInterval?

    public var adherence: Double? { plannedDistance > 0 ? actualDistance / plannedDistance : nil }

    public static let onTrackThreshold = 0.85
    public static let behindThreshold = 0.6
    public static let aboveThreshold = 1.2

    /// Evalúa las 2 últimas semanas completas del plan.
    public static func evaluate(plan: TrainingPlan, runs: [WorkoutSummary], estimate: FitnessEstimate?, today: Date, calendar: Calendar) -> PlanProgress {
        let todayStart = calendar.startOfDay(for: today)
        let completed = plan.weeks.filter { week in
            (calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start) <= todayStart
        }.suffix(2)
        let planned = completed.map(\.distance).reduce(0, +)
        let actual = completed.map { week -> Double in
            let end = calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
            return runs.filter { $0.activity.isRun && $0.start >= week.start && $0.start < end }.compactMap(\.distanceMeters).reduce(0, +)
        }.reduce(0, +)

        let status: Status
        if completed.isEmpty || planned <= 0 {
            status = .notStarted
        } else {
            let ratio = actual / planned
            status = ratio > aboveThreshold ? .abovePlan : (ratio >= onTrackThreshold ? .onTrack : (ratio >= behindThreshold ? .slightlyBehind : .behind))
        }

        var change: Double?
        if let start = plan.vdot, let estimate { change = estimate.vdot - start }
        var projected: TimeInterval?
        if let vdot = estimate?.vdot ?? plan.vdot {
            let weeks = GoalCoach.trainingWeeks(until: plan.goal.raceDate, distance: plan.goal.distance, today: today, calendar: calendar)
            projected = VDOT.raceTime(vdot: vdot + Double(weeks) / GoalCoach.realisticWeeksPerPoint, distance: plan.goal.distance.rawValue)
        }
        return PlanProgress(status: status, plannedDistance: planned, actualDistance: actual, weeksEvaluated: completed.count, vdotChange: change, projectedTime: projected)
    }
}
