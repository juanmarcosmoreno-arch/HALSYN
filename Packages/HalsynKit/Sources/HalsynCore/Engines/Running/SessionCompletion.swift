import Foundation

/// Si una sesión del plan se hizo, comparando con las carreras de ese día.
public enum SessionCompletion: Hashable, Sendable {
    /// Hecha: corriste ese día al menos el 80 % de lo planeado (o, en series,
    /// umbral y test, cualquier carrera ese día: la distancia total varía).
    case done(distance: Double)
    /// Corriste ese día, pero bastante menos de lo planeado.
    case partial(distance: Double)
    /// Ya pasó y no hay ninguna carrera ese día.
    case missed
    case today
    case upcoming
    case rest

    /// Fracción mínima de la distancia planeada para darla por hecha.
    public static let doneFraction = 0.8

    public static func evaluate(_ session: PlannedSession, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> SessionCompletion {
        guard session.kind != .rest else { return .rest }
        let ran = runs
            .filter { $0.activity.isRun && calendar.isDate($0.start, inSameDayAs: session.date) }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
        if ran > 0 {
            let structured = session.kind == .intervals || session.kind == .tempo || session.kind == .test
            if structured || session.distance <= 0 || ran >= session.distance * doneFraction {
                return .done(distance: ran)
            }
            // Hoy todavía puede seguir sumando.
            if calendar.isDate(session.date, inSameDayAs: today) { return .today }
            return .partial(distance: ran)
        }
        let day = calendar.startOfDay(for: session.date)
        let start = calendar.startOfDay(for: today)
        if day < start { return .missed }
        if day == start { return .today }
        return .upcoming
    }

    public var isDone: Bool {
        if case .done = self { return true }
        return false
    }
}

extension PlannedWeek {
    /// Sesiones con carrera hechas y planeadas en la semana (sin descansos).
    public func completion(runs: [WorkoutSummary], today: Date, calendar: Calendar) -> (done: Int, planned: Int) {
        let running = sessions.filter { $0.kind != .rest }
        let done = running.filter { SessionCompletion.evaluate($0, runs: runs, today: today, calendar: calendar).isDone }.count
        return (done, running.count)
    }
}
