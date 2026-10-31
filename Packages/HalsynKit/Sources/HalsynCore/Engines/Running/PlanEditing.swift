import Foundation

/// Cambios a mano en la semana actual del plan: mover o intercambiar una
/// sesión de día, alargarla o acortarla, o saltarla. Solo en esta semana: las
/// siguientes se recalculan cada lunes con lo que corriste.
extension TrainingPlan {
    /// Días a los que se puede mover algo: de hoy al final de esta semana (sin
    /// pasar el día de la carrera).
    public func editableDays(today: Date, calendar: Calendar) -> [Date] {
        guard let week = week(containing: today, calendar: calendar) else { return [] }
        let first = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: week.start)) }
            .filter { $0 >= first && $0 < raceDay }
    }

    /// La sesión de ese día se puede editar (es de esta semana, de hoy en adelante).
    public func canEdit(_ day: Date, today: Date, calendar: Calendar) -> Bool {
        editableDays(today: today, calendar: calendar).contains { calendar.isDate($0, inSameDayAs: day) }
    }

    /// Mueve la sesión de `day` a `target`; si `target` ya tiene una, se
    /// intercambian. `nil` si alguno de los dos días no se puede editar o `day`
    /// no tiene sesión.
    public func moving(sessionOn day: Date, to target: Date, today: Date, calendar: Calendar) -> TrainingPlan? {
        guard !calendar.isDate(day, inSameDayAs: target),
              canEdit(day, today: today, calendar: calendar), canEdit(target, today: today, calendar: calendar),
              let location = location(of: day, calendar: calendar) else { return nil }
        var plan = self
        let targetDay = calendar.startOfDay(for: target)
        let sourceDay = calendar.startOfDay(for: day)
        if let other = plan.location(of: target, calendar: calendar) {
            plan.weeks[other.week].sessions[other.index].date = sourceDay
        }
        plan.weeks[location.week].sessions[location.index].date = targetDay
        plan.weeks[location.week].sessions.sort { $0.date < $1.date }
        return plan
    }

    /// Cambia la sesión de `day` (más corta, más larga, otro reparto).
    public func replacing(sessionOn day: Date, with session: PlannedSession, today: Date, calendar: Calendar) -> TrainingPlan? {
        guard canEdit(day, today: today, calendar: calendar), let location = location(of: day, calendar: calendar) else { return nil }
        var plan = self
        var updated = session
        updated.date = plan.weeks[location.week].sessions[location.index].date
        plan.weeks[location.week].sessions[location.index] = updated
        return plan
    }

    /// Hoy no se corre: la sesión pasa a descanso.
    public func skipping(sessionOn day: Date, today: Date, calendar: Calendar) -> TrainingPlan? {
        guard let session = session(on: day, calendar: calendar) else { return nil }
        return replacing(sessionOn: day, with: PlannedSession(date: session.date, kind: .rest, distance: 0), today: today, calendar: calendar)
    }

    private func location(of day: Date, calendar: Calendar) -> (week: Int, index: Int)? {
        for (w, week) in weeks.enumerated() {
            if let i = week.sessions.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                return (w, i)
            }
        }
        return nil
    }
}

extension PlannedSession {
    /// Qué se puede alargar o acortar en esta sesión.
    public enum Volume: Equatable, Sendable {
        /// Distancia total (rodajes y tirada larga), en pasos de 500 m.
        case distance(Double)
        /// Número de series.
        case repeats(Int)
        /// Bloque continuo del umbral, en pasos de 500 m.
        case block(Double)
    }

    public static let distanceRange: ClosedRange<Double> = 2000...42_000
    public static let blockRange: ClosedRange<Double> = 1000...15_000
    public static let repeatsRange: ClosedRange<Int> = 2...20

    public var volume: Volume? {
        switch kind {
        case .easy, .recovery, .long: .distance(distance)
        case .intervals: repeats.map(Volume.repeats)
        case .tempo: repeatDistance.map(Volume.block)
        case .rest, .test: nil
        }
    }

    /// La misma sesión con otro volumen. La distancia total cambia con él (el
    /// calentamiento y la calma siguen igual).
    public func with(_ volume: Volume) -> PlannedSession {
        var session = self
        switch volume {
        case let .distance(meters):
            session.distance = min(max(meters, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        case let .repeats(count):
            guard let old = repeats, let length = repeatDistance else { return self }
            let new = min(max(count, Self.repeatsRange.lowerBound), Self.repeatsRange.upperBound)
            session.repeats = new
            session.distance = max(0, distance + Double(new - old) * length)
        case let .block(meters):
            guard let old = repeatDistance else { return self }
            let new = min(max(meters, Self.blockRange.lowerBound), Self.blockRange.upperBound)
            session.repeatDistance = new
            session.distance = max(0, distance + (new - old) * Double(repeats ?? 1))
        }
        return session
    }

    /// Duración aproximada al ritmo del plan (centro del rango); `nil` sin ritmo.
    public var estimatedDuration: TimeInterval? {
        guard let pace, distance > 0 else { return nil }
        return distance / 1000 * pace.center.secondsPerKilometer
    }
}
