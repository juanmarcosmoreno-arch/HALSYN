import Foundation

/// Tipo de sesión de un plan.
public enum SessionKind: String, Codable, Hashable, CaseIterable, Sendable {
    case easy
    case long
    case tempo
    case intervals
    case recovery
    case rest

    public var title: String {
        switch self {
        case .easy: "Rodaje suave"
        case .long: "Tirada larga"
        case .tempo: "Ritmo umbral"
        case .intervals: "Series"
        case .recovery: "Rodaje de recuperación"
        case .rest: "Descanso"
        }
    }

    public var systemImage: String {
        switch self {
        case .easy, .recovery: "figure.run"
        case .long: "road.lanes"
        case .tempo: "speedometer"
        case .intervals: "repeat"
        case .rest: "bed.double"
        }
    }

    public var isHard: Bool { self == .tempo || self == .intervals }
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

    public init(distance: RaceDistance, raceDate: Date, runsPerWeek: Int, longRunWeekday: Int = 1, gymWeekdays: Set<Int> = []) {
        self.distance = distance
        self.raceDate = raceDate
        self.runsPerWeek = min(max(runsPerWeek, 3), 5)
        self.longRunWeekday = longRunWeekday
        self.gymWeekdays = gymWeekdays
    }
}

public struct TrainingPlan: Codable, Hashable, Sendable {
    public var goal: PlanGoal
    public var paces: TrainingPaces
    public var weeks: [PlannedWeek]
    public var createdAt: Date
    /// Kilómetros por semana de partida (media de tus últimas 4 semanas).
    public var startingWeeklyDistance: Double

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

        let paces = TrainingPaces.from(tenK: tenKTime, target: goal.distance)
        let peak = max(peakVolume(goal.distance, runsPerWeek: goal.runsPerWeek), weeklyDistance)
        let taper = taperWeeks(goal.distance)
        var volume = max(weeklyDistance, 12_000)
        var weeks: [PlannedWeek] = []

        for index in 0..<weekCount {
            guard let weekStart = calendar.date(byAdding: .day, value: 7 * index, to: start) else { continue }
            let weeksLeft = weekCount - 1 - index
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
                phase = index < (weekCount - taper) / 2 ? .base : .build
                if index > 0 { volume = min(volume * 1.08, peak) }
                weekVolume = volume
            }
            weeks.append(PlannedWeek(index: index, start: weekStart, phase: phase, sessions: sessions(
                week: weekStart, phase: phase, volume: weekVolume, goal: goal, paces: paces, raceDay: raceDay, calendar: calendar
            )))
        }
        return TrainingPlan(goal: goal, paces: paces, weeks: weeks, createdAt: today, startingWeeklyDistance: weeklyDistance)
    }

    /// Reparte el volumen semanal en sesiones.
    static func sessions(week start: Date, phase: PlannedWeek.Phase, volume: Double, goal: PlanGoal, paces: TrainingPaces, raceDay: Date, calendar: Calendar) -> [PlannedSession] {
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
            if position < qualitySlots, let kind = quality.dropFirst(position).first ?? quality.first {
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
