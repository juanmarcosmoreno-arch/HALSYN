import Foundation

/// Tipo de sesión de un plan.
public enum SessionKind: String, Codable, Hashable, CaseIterable, Sendable {
    case easy
    case long
    case tempo
    case intervals
    case recovery
    case rest
    /// Test a tope para medir tu forma (VDOT).
    case test

    public var title: String {
        switch self {
        case .easy: "Rodaje suave"
        case .long: "Tirada larga"
        case .tempo: "Ritmo umbral"
        case .intervals: "Series"
        case .recovery: "Rodaje de recuperación"
        case .rest: "Descanso"
        case .test: "Test de forma"
        }
    }

    public var systemImage: String {
        switch self {
        case .easy, .recovery: "figure.run"
        case .long: "road.lanes"
        case .tempo: "speedometer"
        case .intervals: "repeat"
        case .rest: "bed.double"
        case .test: "stopwatch"
        }
    }

    public var isHard: Bool { self == .tempo || self == .intervals || self == .test }
}

/// Ritmos de entrenamiento derivados de tu forma actual (s/km).
public struct TrainingPaces: Codable, Hashable, Sendable {
    public var easy: PaceRange
    public var tempo: PaceRange
    public var interval: PaceRange
    public var race: Pace

    /// A partir del tiempo estimado en 10 km (Riegel desde tus carreras):
    /// - series ≈ ritmo de 5 km;
    /// - umbral ≈ ritmo de unos 60 min de carrera (entre 10 km y media);
    /// - suave ≈ ritmo de 10 km + 60–90 s/km.
    public static func from(tenK time: TimeInterval, target: RaceDistance) -> TrainingPaces {
        let tenK = time / 10
        let fiveK = RacePredictor.riegel(time: time, from: 10_000, to: 5000) / 5
        let half = RacePredictor.riegel(time: time, from: 10_000, to: RaceDistance.half.rawValue) / (RaceDistance.half.rawValue / 1000)
        let threshold = (tenK + half) / 2
        let race = RacePredictor.riegel(time: time, from: 10_000, to: target.rawValue) / (target.rawValue / 1000)
        return TrainingPaces(
            easy: PaceRange(fastest: tenK + 60, slowest: tenK + 90),
            tempo: PaceRange(center: Pace(secondsPerKilometer: threshold), tolerance: 5),
            interval: PaceRange(center: Pace(secondsPerKilometer: fiveK), tolerance: 5),
            race: Pace(secondsPerKilometer: race)
        )
    }
}

/// Una sesión concreta del plan.
public struct PlannedSession: Codable, Hashable, Identifiable, Sendable {
    public var date: Date
    public var kind: SessionKind
    /// Distancia total aproximada en metros (0 en descanso).
    public var distance: Double
    /// Series: repeticiones × metros; umbral: un bloque continuo.
    public var repeats: Int?
    public var repeatDistance: Double?
    public var pace: PaceRange?

    public var id: Date { date }
}

public struct PlannedWeek: Codable, Hashable, Identifiable, Sendable {
    public var index: Int
    public var start: Date
    public var phase: Phase
    public var sessions: [PlannedSession]

    public enum Phase: String, Codable, Hashable, Sendable {
        case base, build, recovery, taper, race

        public var title: String {
            switch self {
            case .base: "Base"
            case .build: "Desarrollo"
            case .recovery: "Asimilación"
            case .taper: "Afinamiento"
            case .race: "Semana de carrera"
            }
        }
    }

    public var id: Int { index }
    public var distance: Double { sessions.map(\.distance).reduce(0, +) }
}

/// Lo que eligió el usuario.
public struct PlanGoal: Codable, Hashable, Sendable {
    public var distance: RaceDistance
    public var raceDate: Date
    /// Días de carrera por semana (3–5).
    public var runsPerWeek: Int
    /// Día de la tirada larga (1 = domingo … 7 = sábado).
    public var longRunWeekday: Int
    /// Días de gimnasio (1 = domingo … 7 = sábado). Opcional para planes guardados antes.
    public var gymWeekdays: Set<Int>?
    /// Tiempo objetivo en segundos (opcional).
    public var goalTime: TimeInterval?

    public init(distance: RaceDistance, raceDate: Date, runsPerWeek: Int, longRunWeekday: Int = 1, gymWeekdays: Set<Int> = [], goalTime: TimeInterval? = nil) {
        self.distance = distance
        self.raceDate = raceDate
        self.runsPerWeek = min(max(runsPerWeek, 3), 5)
        self.longRunWeekday = longRunWeekday
        self.gymWeekdays = gymWeekdays
        self.goalTime = goalTime
    }
}

public struct TrainingPlan: Codable, Hashable, Sendable {
    public var goal: PlanGoal
    public var paces: TrainingPaces
    public var weeks: [PlannedWeek]
    public var createdAt: Date
    /// Kilómetros por semana de partida (media de tus últimas 4 semanas).
    public var startingWeeklyDistance: Double
    /// VDOT con el que se calcularon los ritmos (planes nuevos).
    public var vdot: Double?
    /// Último reajuste semanal.
    public var lastAdjustment: PlanAdjustment?

    public func session(on day: Date, calendar: Calendar) -> PlannedSession? {
        weeks.lazy.flatMap(\.sessions).first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    public func week(containing day: Date, calendar: Calendar) -> PlannedWeek? {
        weeks.first { week in
            guard let end = calendar.date(byAdding: .day, value: 7, to: week.start) else { return false }
            return day >= week.start && day < end
        }
    }
}

extension RaceDistance: Codable {}

/// Qué cambió en el último reajuste del plan.
public struct PlanAdjustment: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Hashable, Sendable {
        /// Hiciste bastante menos de lo planeado: se baja el volumen.
        case behind
        /// Vas según lo previsto: el plan sigue igual.
        case onTrack
        /// Hiciste más de lo planeado: no se sube más deprisa.
        case abovePlan
        /// Tu forma cambió (test o carrera): nuevos ritmos.
        case fitnessUpdated
    }

    public var date: Date
    public var reason: Reason
    /// Volumen previsto para la semana siguiente antes y después (m).
    public var previousVolume: Double
    public var newVolume: Double
    /// Cambio de VDOT aplicado a los ritmos, si lo hubo.
    public var vdotChange: Double?

    public init(date: Date, reason: Reason, previousVolume: Double, newVolume: Double, vdotChange: Double? = nil) {
        self.date = date
        self.reason = reason
        self.previousVolume = previousVolume
        self.newVolume = newVolume
        self.vdotChange = vdotChange
    }
}

/// Genera un plan semanal hacia una carrera.
///
/// Principios (prácticas habituales de entrenamiento, no una prescripción médica):
/// - Parte de tu volumen actual y sube como mucho un 8 % por semana; cada
///   cuarta semana baja un 20 % para asimilar.
/// - Unos 80 % suave y 20 % intenso: una sesión de calidad por semana con 3
///   días, dos con 4–5 (series y umbral), más la tirada larga.
/// - Tirada larga ≈ 30 % del volumen, con tope por distancia objetivo.
/// - Afinamiento final: 1 semana (5–10 km), 2 (media) o 3 (maratón).
public enum TrainingPlanGenerator {
    public static let maximumWeeks = 24
    public static let minimumWeeks = 4

    static func longRunCap(_ distance: RaceDistance) -> Double {
        switch distance {
        case .fiveK: 10_000
        case .tenK: 15_000
        case .half: 19_000
        case .marathon: 32_000
        }
    }

    static func peakVolume(_ distance: RaceDistance, runsPerWeek: Int) -> Double {
        let base: Double = switch distance {
        case .fiveK: 30_000
        case .tenK: 40_000
        case .half: 50_000
        case .marathon: 65_000
        }
        return base * (0.8 + 0.1 * Double(runsPerWeek - 3))
    }

    static func taperWeeks(_ distance: RaceDistance) -> Int {
        switch distance {
        case .fiveK, .tenK: 1
        case .half: 2
        case .marathon: 3
        }
    }

    /// Volumen semanal medio de las últimas 4 semanas (m).
    public static func recentWeeklyDistance(_ runs: [WorkoutSummary], endingOn end: Date, calendar: Calendar) -> Double {
        guard let start = calendar.date(byAdding: .day, value: -28, to: end) else { return 0 }
        let total = runs.filter { $0.activity.isRun && $0.start >= start && $0.start <= end }.compactMap(\.distanceMeters).reduce(0, +)
        return total / 4
    }

    public static func make(goal: PlanGoal, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> TrainingPlan? {
        let predictions = RacePredictor.predictions(from: runs, endingOn: today, calendar: calendar)
        guard let tenK = predictions.first(where: { $0.distance == .tenK }) else { return nil }
        return make(goal: goal, tenKTime: tenK.time, weeklyDistance: recentWeeklyDistance(runs, endingOn: today, calendar: calendar), today: today, calendar: calendar)
    }

    public static func make(goal: PlanGoal, tenKTime: TimeInterval, weeklyDistance: Double, today: Date, calendar: Calendar) -> TrainingPlan? {
        make(goal: goal, paces: TrainingPaces.from(tenK: tenKTime, target: goal.distance), weeklyDistance: weeklyDistance, initialTest: false, today: today, calendar: calendar)
    }

    /// Plan a partir de tu forma (VDOT). Si la forma sale de entrenamientos o
    /// tiene más de 6 semanas, la primera semana empieza con un test.
    public static func make(goal: PlanGoal, estimate: FitnessEstimate, weeklyDistance: Double, today: Date, calendar: Calendar) -> TrainingPlan? {
        let paces = TrainingPaces.from(vdot: estimate.vdot, target: goal.distance, goalTime: goal.goalTime)
        guard var plan = make(goal: goal, paces: paces, weeklyDistance: weeklyDistance, initialTest: estimate.needsTest(today: today, calendar: calendar), today: today, calendar: calendar) else { return nil }
        plan.vdot = estimate.vdot
        return plan
    }

    /// Distancia del test: 3 km si aún corres poco por semana, 5 km si no.
    public static func testDistance(weeklyDistance: Double) -> Double {
        weeklyDistance < 15_000 ? 3000 : 5000
    }

    static func make(goal: PlanGoal, paces: TrainingPaces, weeklyDistance: Double, initialTest: Bool, today: Date, calendar: Calendar) -> TrainingPlan? {
        let firstDay = calendar.startOfDay(for: today)
        // Las semanas empiezan el lunes siguiente a hoy (o hoy si es lunes).
        var mondayComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstDay)
        mondayComponents.weekday = 2
        guard var start = calendar.date(from: mondayComponents) else { return nil }
        if start < firstDay { start = calendar.date(byAdding: .day, value: 7, to: start) ?? start }
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        guard let days = calendar.dateComponents([.day], from: start, to: raceDay).day else { return nil }
        let weekCount = min(days / 7 + 1, maximumWeeks)
        guard weekCount >= minimumWeeks else { return nil }

        let weeks = buildWeeks(
            start: start, firstIndex: 0, count: weekCount,
            startVolume: max(weeklyDistance, 12_000),
            peak: max(peakVolume(goal.distance, runsPerWeek: goal.runsPerWeek), weeklyDistance),
            goal: goal, paces: paces, raceDay: raceDay,
            initialTest: initialTest, testDistance: testDistance(weeklyDistance: weeklyDistance),
            calendar: calendar
        )
        return TrainingPlan(goal: goal, paces: paces, weeks: weeks, createdAt: today, startingWeeklyDistance: weeklyDistance)
    }

    /// Semanas desde `start` hasta la carrera. `firstIndex` numera la primera
    /// (para reajustes a mitad de plan) y marca el ritmo de las semanas de
    /// asimilación (cada cuarta) y de los tests (cada 6 semanas).
    static func buildWeeks(start: Date, firstIndex: Int, count: Int, startVolume: Double, peak: Double, goal: PlanGoal, paces: TrainingPaces, raceDay: Date, initialTest: Bool, testDistance: Double, calendar: Calendar) -> [PlannedWeek] {
        let taper = taperWeeks(goal.distance)
        let totalWeeks = firstIndex + count
        var volume = startVolume
        var weeks: [PlannedWeek] = []
        for local in 0..<count {
            let index = firstIndex + local
            guard let weekStart = calendar.date(byAdding: .day, value: 7 * local, to: start) else { continue }
            let weeksLeft = count - 1 - local
            let phase: PlannedWeek.Phase
            var weekVolume: Double
            if weeksLeft == 0 {
                phase = .race
                weekVolume = peak * 0.4
            } else if weeksLeft <= taper {
                phase = .taper
                weekVolume = peak * (weeksLeft == taper ? 0.75 : 0.6)
            } else if (index + 1) % 4 == 0 {
                phase = .recovery
                weekVolume = volume * 0.8
            } else {
                phase = index < (totalWeeks - taper) / 2 ? .base : .build
                if local > 0 { volume = min(volume * 1.08, peak) }
                weekVolume = volume
            }
            // Test: al empezar si la forma no es fiable y luego cada 6 semanas,
            // solo en semanas normales y con al menos 3 semanas hasta la carrera.
            let wantsTest = (local == 0 && initialTest) || (index > 0 && index % testEveryWeeks == 0)
            let includesTest = wantsTest && (phase == .base || phase == .build) && weeksLeft >= 3
            weeks.append(PlannedWeek(index: index, start: weekStart, phase: phase, sessions: sessions(
                week: weekStart, phase: phase, volume: weekVolume, goal: goal, paces: paces, raceDay: raceDay,
                test: includesTest ? testDistance : nil, calendar: calendar
            )))
        }
        return weeks
    }

    public static let testEveryWeeks = 6

    /// `true` si toca el reajuste de esta semana (una vez por semana, desde la segunda).
    public static func needsWeeklyReplan(_ plan: TrainingPlan, today: Date, calendar: Calendar) -> Bool {
        guard let current = plan.week(containing: today, calendar: calendar), current.index > 0, current.phase != .race else { return false }
        let last = plan.lastAdjustment?.date ?? plan.createdAt
        return last < current.start
    }

    /// Reajusta las semanas que quedan (desde la siguiente) con lo que corriste
    /// de verdad y tu forma más reciente. Las semanas pasadas y la actual no
    /// cambian.
    ///
    /// - Si hiciste menos de lo planeado, la siguiente semana parte de tu
    ///   volumen real y sube como mucho un 8 por ciento: lo perdido no se recupera.
    /// - Si hiciste más, no se sube más deprisa de lo previsto.
    /// - Si hay un test o una carrera nuevos, los ritmos se recalculan.
    public static func replan(_ plan: TrainingPlan, runs: [WorkoutSummary], estimate: FitnessEstimate?, today: Date, calendar: Calendar) -> TrainingPlan {
        guard let current = plan.week(containing: today, calendar: calendar),
              let nextStart = calendar.date(byAdding: .day, value: 7, to: current.start) else { return plan }
        let future = plan.weeks.filter { $0.start >= nextStart }
        guard let nextOld = future.first else { return plan }

        var updated = plan
        var vdotChange: Double?
        if let estimate, abs(estimate.vdot - (plan.vdot ?? 0)) >= 0.5 {
            vdotChange = plan.vdot.map { estimate.vdot - $0 }
            updated.vdot = estimate.vdot
            updated.paces = TrainingPaces.from(vdot: estimate.vdot, target: plan.goal.distance, goalTime: plan.goal.goalTime)
        }

        let progress = PlanProgress.evaluate(plan: plan, runs: runs, estimate: estimate, today: today, calendar: calendar)
        let actual = progress.weeksEvaluated > 0 ? progress.actualDistance / Double(progress.weeksEvaluated) : plan.startingWeeklyDistance
        // Nivel de volumen previsto: la primera semana normal que queda.
        let plannedLevel = future.first { $0.phase == .base || $0.phase == .build }?.distance ?? nextOld.distance
        let startVolume = min(plannedLevel, max(actual, 12_000) * 1.08)

        let previousWeek = plan.weeks.first { $0.index == current.index - 1 }
        let recentTest = (current.sessions + (previousWeek?.sessions ?? [])).contains { $0.kind == .test }
        let needsTest = (estimate?.needsTest(today: today, calendar: calendar) ?? true) && !recentTest

        let raceDay = calendar.startOfDay(for: plan.goal.raceDate)
        let newWeeks = buildWeeks(
            start: nextStart, firstIndex: nextOld.index, count: future.count,
            startVolume: startVolume,
            peak: max(peakVolume(plan.goal.distance, runsPerWeek: plan.goal.runsPerWeek), plan.startingWeeklyDistance),
            goal: plan.goal, paces: updated.paces, raceDay: raceDay,
            initialTest: needsTest, testDistance: testDistance(weeklyDistance: actual),
            calendar: calendar
        )
        updated.weeks = plan.weeks.filter { $0.start < nextStart } + newWeeks

        let reason: PlanAdjustment.Reason
        if vdotChange != nil || (plan.vdot == nil && updated.vdot != nil) {
            reason = .fitnessUpdated
        } else {
            switch progress.status {
            case .behind, .slightlyBehind: reason = startVolume < plannedLevel - 500 ? .behind : .onTrack
            case .abovePlan: reason = .abovePlan
            case .onTrack, .notStarted: reason = .onTrack
            }
        }
        updated.lastAdjustment = PlanAdjustment(date: today, reason: reason, previousVolume: nextOld.distance, newVolume: newWeeks.first?.distance ?? nextOld.distance, vdotChange: vdotChange)
        return updated
    }

    /// Reparte el volumen semanal en sesiones.
    static func sessions(week start: Date, phase: PlannedWeek.Phase, volume: Double, goal: PlanGoal, paces: TrainingPaces, raceDay: Date, test: Double? = nil, calendar: Calendar) -> [PlannedSession] {
        // Días de carrera según cuántos por semana (desde el lunes, 0 = lunes).
        let longOffset = (goal.longRunWeekday + 5) % 7
        let pattern: [Int] = switch goal.runsPerWeek {
        case 3: [1, 3]
        case 4: [1, 3, 4]
        default: [0, 1, 3, 4]
        }
        // Las sesiones de calidad van primero en días lejos del gimnasio (ni ese
        // día ni el siguiente): la fuerza también cansa las piernas.
        let gym = goal.gymWeekdays ?? []
        func weekday(_ offset: Int) -> Int { (offset + 1) % 7 + 1 }
        func nearGym(_ offset: Int) -> Bool { gym.contains(weekday(offset)) || gym.contains(weekday(offset + 6)) }
        let qualityCount = phase == .base || phase == .recovery || phase == .race ? 1 : (goal.runsPerWeek >= 4 ? 2 : 1)
        let runDays = goal.runsPerWeek - 1
        let defaultDays = Array(pattern.filter { $0 != longOffset }.prefix(runDays))
        let dayBeforeLong = (longOffset + 6) % 7
        // Días buenos para calidad: lejos del gimnasio, no la víspera de la tirada larga
        // y no seguidos entre sí.
        var qualityDays: [Int] = []
        for offset in [1, 3, 4, 0, 2, 5, 6] where offset != longOffset && offset != dayBeforeLong && !nearGym(offset) {
            guard qualityDays.count < qualityCount, qualityDays.allSatisfy({ abs($0 - offset) > 1 }) else { continue }
            qualityDays.append(offset)
        }
        let others: [Int]
        if qualityDays.isEmpty {
            others = defaultDays
        } else {
            // El resto, suaves: primero los días habituales, luego cualquiera libre.
            var easyDays = defaultDays.filter { !qualityDays.contains($0) }
            for offset in [1, 3, 4, 0, 2, 5, 6] where easyDays.count < runDays - qualityDays.count
                && offset != longOffset && !qualityDays.contains(offset) && !easyDays.contains(offset) {
                easyDays.append(offset)
            }
            others = qualityDays + easyDays.prefix(runDays - qualityDays.count)
        }
        let qualitySlots = qualityDays.isEmpty ? qualityCount : qualityDays.count

        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: start) ?? start }
        func round(_ meters: Double) -> Double { (meters / 500).rounded() * 500 }

        var result: [PlannedSession] = []
        let long = phase == .race ? 0 : min(round(volume * 0.3), longRunCap(goal.distance))
        var remaining = volume - long
        let quality: [SessionKind] = phase == .base ? [.tempo] : [.intervals, .tempo]
        for (position, offset) in others.enumerated() {
            let date = day(offset)
            if date >= raceDay { continue }
            let share = remaining / Double(others.count - position)
            remaining -= share
            if position == 0, let test {
                // El test ocupa la primera sesión de calidad: calentamiento y
                // vuelta a la calma de unos 3 km en total.
                result.append(PlannedSession(date: date, kind: .test, distance: test + 3000, repeats: 1, repeatDistance: test))
            } else if position < qualitySlots, let kind = quality.dropFirst(position).first ?? quality.first {
                result.append(qualitySession(kind, date: date, distance: round(share), paces: paces, phase: phase))
            } else {
                result.append(PlannedSession(date: date, kind: phase == .recovery ? .recovery : .easy, distance: max(round(share), 3000), pace: paces.easy))
            }
        }
        if phase == .race {
            result.append(PlannedSession(date: raceDay, kind: .long, distance: goal.distance.rawValue, pace: PaceRange(center: paces.race, tolerance: 5)))
        } else {
            let date = day(longOffset)
            if date < raceDay {
                result.append(PlannedSession(date: date, kind: .long, distance: max(long, 6000), pace: paces.easy))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func qualitySession(_ kind: SessionKind, date: Date, distance: Double, paces: TrainingPaces, phase: PlannedWeek.Phase) -> PlannedSession {
        switch kind {
        case .intervals:
            // 800 m a ritmo de 5 km; el número crece con la fase.
            let repeats = phase == .build ? 6 : (phase == .taper ? 4 : 5)
            return PlannedSession(date: date, kind: .intervals, distance: max(distance, Double(repeats) * 800 + 4000), repeats: repeats, repeatDistance: 800, pace: paces.interval)
        default:
            // Bloque continuo a ritmo umbral de unos 20–30 min.
            let block = phase == .build ? 6000.0 : 4000
            return PlannedSession(date: date, kind: .tempo, distance: max(distance, block + 4000), repeats: 1, repeatDistance: block, pace: paces.tempo)
        }
    }
}

/// Ajuste de la sesión de hoy según la recuperación y las señales.
public enum PlanAdaptation {
    public enum Change: String, Hashable, Sendable {
        case none
        /// Calidad → suave y algo más corta.
        case softened
        /// Cualquier sesión → descanso o paseo.
        case rested
    }

    public static func adapt(_ session: PlannedSession, guidance: TrainingGuidance, paces: TrainingPaces) -> (session: PlannedSession, change: Change) {
        guard session.kind != .rest else { return (session, .none) }
        switch guidance {
        case .rest:
            return (PlannedSession(date: session.date, kind: .rest, distance: 0), .rested)
        case .easy where session.kind.isHard || session.kind == .long:
            let shorter = (session.distance * 0.7 / 500).rounded() * 500
            return (PlannedSession(date: session.date, kind: .easy, distance: max(shorter, 3000), pace: paces.easy), .softened)
        default:
            return (session, .none)
        }
    }

    /// Plan de intervalos para el reloj (calentamiento, bloques y calma).
    public static func intervalPlan(for session: PlannedSession, id: String, name: String) -> IntervalPlan? {
        switch session.kind {
        case .rest:
            return nil
        case .test:
            // Solo el test: el calentamiento se hace antes, sin grabar, para que
            // el entrenamiento guardado sea exactamente el esfuerzo a tope.
            guard let length = session.repeatDistance else { return nil }
            return IntervalPlan(id: id, name: name, warmup: nil, work: .distance(length), workPace: nil, recovery: .open, repeats: 1, cooldown: nil)
        case .intervals, .tempo:
            guard let repeats = session.repeats, let length = session.repeatDistance else { return nil }
            return IntervalPlan(
                id: id, name: name,
                warmup: .distance(2000),
                work: .distance(length), workPace: session.pace,
                recovery: session.kind == .intervals ? .time(120) : .open,
                repeats: repeats,
                cooldown: .distance(2000)
            )
        default:
            return IntervalPlan(id: id, name: name, warmup: nil, work: .distance(session.distance), workPace: session.pace, recovery: .open, repeats: 1, cooldown: nil)
        }
    }
}
