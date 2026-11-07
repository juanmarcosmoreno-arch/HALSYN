import Foundation

/// Una molestia o dolor que registra el corredor.
public struct Complaint: Codable, Hashable, Identifiable, Sendable {
    public enum Area: String, Codable, CaseIterable, Identifiable, Sendable {
        case foot, ankle, achilles, calf, shin, knee, hamstring, quadriceps, hip, back, other

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .foot: "Pie"
            case .ankle: "Tobillo"
            case .achilles: "Tendón de Aquiles"
            case .calf: "Gemelo"
            case .shin: "Tibia"
            case .knee: "Rodilla"
            case .hamstring: "Isquiotibiales"
            case .quadriceps: "Cuádriceps"
            case .hip: "Cadera"
            case .back: "Espalda"
            case .other: "Otra zona"
            }
        }
    }

    public var id: UUID
    public var date: Date
    public var area: Area
    /// 0 (nada) a 10 (máximo).
    public var pain: Int
    public var note: String?
    public var resolvedAt: Date?

    public init(id: UUID = UUID(), date: Date, area: Area, pain: Int, note: String? = nil, resolvedAt: Date? = nil) {
        self.id = id
        self.date = date
        self.area = area
        self.pain = min(max(pain, 0), 10)
        self.note = note
        self.resolvedAt = resolvedAt
    }

    /// Sigue contando: sin resolver y registrada en los últimos 14 días.
    public func isActive(on day: Date, calendar: Calendar) -> Bool {
        guard resolvedAt == nil, date <= day else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: day)).day ?? 0
        return days <= PlanAdvisor.complaintDays
    }
}

/// Ajustes automáticos del plan para los próximos días, con su porqué.
public struct PlanAdvice: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// Recuperación baja varios días (valores y tu mediana de 28 días).
        case lowRecovery(lowDays: Int, recent: Int, usual: Int)
        /// Kilómetros de los últimos 7 días frente a tu media semanal previa.
        case volumeSpike(ratio: Double)
        /// Sesiones exigentes (pulso alto) en los últimos 7 días.
        case manyHardSessions(count: Int)
        /// Molestia moderada (4–6).
        case complaint(area: Complaint.Area, pain: Int)
        /// Dolor fuerte (7 o más).
        case severeComplaint(area: Complaint.Area, pain: Int)
        /// Dos sesiones exigentes en días seguidos.
        case consecutiveHardDays
        /// Enfermedad, fiebre o lesión registrada (en curso o terminada hace ≤ 3 días).
        case healthEvent(kind: HealthEvent.Kind, title: String, ongoing: Bool)
    }

    public enum Change: Hashable, Sendable {
        /// Sesión exigente → rodaje suave más corto.
        case softened
        /// Misma sesión, más corta (fracción que queda).
        case shortened(Double)
        /// Descanso.
        case rested
    }

    public struct Adjustment: Hashable, Identifiable, Sendable {
        public let original: PlannedSession
        public let adjusted: PlannedSession
        public let change: Change
        public var id: Date { original.date }
    }

    public let reasons: [Reason]
    public let adjustments: [Adjustment]

    public var isEmpty: Bool { adjustments.isEmpty }

    /// Identifica este conjunto de ajustes (para recordar si el usuario los rechazó).
    public var signature: String {
        adjustments.map { "\(Int($0.original.date.timeIntervalSince1970))-\($0.change)" }.joined(separator: "|")
    }
}

/// Ajusta los próximos días del plan según cómo responde el corredor.
///
/// Reglas (RUNNING_ENGINE.md, "Plan adaptativo"); una sola señal aislada no
/// cambia el plan:
/// - **Señales de fatiga** (se necesitan 2 de 3):
///   1. Recuperación baja: al menos 2 de los últimos 3 días por debajo de
///      max(50, tu mediana de 28 días − 15).
///   2. Volumen brusco: km de los últimos 7 días ≥ 1,5 × tu media semanal de
///      las 4 semanas anteriores (con al menos 10 km de media).
///   3. Muchas sesiones exigentes: 3 o más carreras "fuertes" o más en 7 días
///      (`EffortClassifier`).
///   Con 2 o más: la próxima sesión exigente de los próximos 4 días pasa a
///   rodaje suave (80 % de la distancia) y la tirada larga de esos días se
///   acorta al 85 % (salvo en la semana de la carrera, que ya es de afinamiento).
/// - **Molestia** activa (últimos 14 días, sin resolver):
///   4–6: las sesiones exigentes de los próximos 7 días pasan a rodaje suave y
///   la tirada larga se acorta al 80 %; 7 o más: descanso los próximos 3 días y
///   rodajes suaves el resto de la semana (y se sugiere consultar a un profesional).
/// - **Evento de salud** (enfermedad, fiebre o lesión registrada, en curso o
///   terminada hace 3 días o menos): con fiebre o lesión en curso, descanso los
///   próximos 2 días; en todos los casos, las sesiones exigentes de la semana
///   pasan a rodaje suave y la tirada larga se acorta al 80 % (vuelta gradual).
/// - **Seguridad, siempre**: nunca dos sesiones exigentes en días seguidos; la
///   segunda pasa a rodaje suave.
/// - **Nunca se compensa**: ningún ajuste sube la distancia ni la intensidad
///   para recuperar sesiones perdidas.
/// - Solo cambia los próximos 7 días (desde hoy) y no toca el plan guardado:
///   se aplica al mostrarlo y se puede rechazar.
public enum PlanAdvisor {
    public static let horizonDays = 7
    public static let fatigueHorizonDays = 4
    public static let complaintDays = 14
    public static let softenedFraction = 0.8

    public static func advise(
        plan: TrainingPlan,
        today: Date,
        calendar: Calendar,
        recovery: [(day: Date, value: Int?)],
        runs: [WorkoutSummary],
        maxHeartRate: Double?,
        complaints: [Complaint],
        healthEvents: [HealthEvent] = []
    ) -> PlanAdvice {
        let todayStart = calendar.startOfDay(for: today)
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: todayStart) else { return PlanAdvice(reasons: [], adjustments: []) }
        var sessions = plan.weeks.flatMap(\.sessions).filter { $0.date >= todayStart && $0.date < horizonEnd }.sorted { $0.date < $1.date }
        let originals = Dictionary(uniqueKeysWithValues: sessions.map { ($0.date, $0) })
        var changes: [Date: PlanAdvice.Change] = [:]
        var reasons: [PlanAdvice.Reason] = []
        let raceWeek = (calendar.dateComponents([.day], from: todayStart, to: calendar.startOfDay(for: plan.goal.raceDate)).day ?? 99) <= 7
        func daysFromToday(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: todayStart, to: calendar.startOfDay(for: date)).day ?? 0
        }
        func soften(_ index: Int) {
            let session = sessions[index]
            guard session.kind.isHard, session.date != plan.goal.raceDate else { return }
            sessions[index] = PlannedSession(date: session.date, kind: .easy, distance: (session.distance * softenedFraction).rounded(), pace: plan.paces.easy)
            changes[session.date] = .softened
        }
        func shorten(_ index: Int, to fraction: Double) {
            let session = sessions[index]
            guard session.kind == .long || session.kind == .easy else { return }
            sessions[index].distance = (session.distance * fraction).rounded()
            if case .softened = changes[session.date] { return }
            changes[session.date] = .shortened(fraction)
        }

        // 1. Molestias.
        let active = complaints.filter { $0.isActive(on: today, calendar: calendar) }
        if let worst = active.max(by: { $0.pain < $1.pain }) {
            if worst.pain >= 7 {
                reasons.append(.severeComplaint(area: worst.area, pain: worst.pain))
                for index in sessions.indices where sessions[index].kind != .rest {
                    if daysFromToday(sessions[index].date) < 3 {
                        let session = sessions[index]
                        sessions[index] = PlannedSession(date: session.date, kind: .rest, distance: 0)
                        changes[session.date] = .rested
                    } else {
                        soften(index)
                    }
                }
            } else if worst.pain >= 4 {
                reasons.append(.complaint(area: worst.area, pain: worst.pain))
                for index in sessions.indices {
                    if sessions[index].kind.isHard { soften(index) } else if sessions[index].kind == .long { shorten(index, to: 0.8) }
                }
            }
        }

        // 1b. Eventos de salud: vuelta gradual, sin penalizar.
        let recentHealth = healthEvents.filter { event in
            guard event.kind.affectsTraining, event.start <= today else { return false }
            let since = calendar.dateComponents([.day], from: event.lastDay(today: today, calendar: calendar), to: todayStart).day ?? 99
            return since <= 3
        }
        if let event = recentHealth.max(by: { ($0.isOngoing ? 1 : 0, $0.start) < ($1.isOngoing ? 1 : 0, $1.start) }) {
            reasons.append(.healthEvent(kind: event.kind, title: event.title, ongoing: event.isOngoing))
            let restNow = recentHealth.contains { $0.isOngoing && ($0.kind == .fever || $0.kind == .injury) }
            for index in sessions.indices where sessions[index].kind != .rest {
                if restNow, daysFromToday(sessions[index].date) < 2 {
                    let session = sessions[index]
                    sessions[index] = PlannedSession(date: session.date, kind: .rest, distance: 0)
                    changes[session.date] = .rested
                } else if sessions[index].kind.isHard {
                    soften(index)
                } else if sessions[index].kind == .long {
                    shorten(index, to: 0.8)
                }
            }
        }

        // 2. Señales de fatiga (2 de 3).
        var fatigue: [PlanAdvice.Reason] = []
        if let low = lowRecovery(recovery, today: today, calendar: calendar) { fatigue.append(low) }
        if let ratio = volumeRatio(runs, today: today, calendar: calendar), ratio >= 1.5 { fatigue.append(.volumeSpike(ratio: ratio)) }
        let hard = hardSessions(runs, maxHeartRate: maxHeartRate, today: today, calendar: calendar)
        if hard >= 3 { fatigue.append(.manyHardSessions(count: hard)) }
        if fatigue.count >= 2 {
            reasons += fatigue
            if let index = sessions.indices.first(where: { sessions[$0].kind.isHard && daysFromToday(sessions[$0].date) < fatigueHorizonDays }) {
                soften(index)
            }
            if !raceWeek {
                for index in sessions.indices where sessions[index].kind == .long && daysFromToday(sessions[index].date) < fatigueHorizonDays {
                    shorten(index, to: 0.85)
                }
            }
        }

        // 3. Seguridad: nunca dos exigentes en días seguidos.
        var consecutive = false
        for index in sessions.indices.dropFirst() {
            let previous = sessions[index - 1], current = sessions[index]
            if previous.kind.isHard, current.kind.isHard,
               calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.date), to: calendar.startOfDay(for: current.date)).day == 1 {
                soften(index)
                consecutive = true
            }
        }
        if consecutive { reasons.append(.consecutiveHardDays) }

        let adjustments = sessions.compactMap { session -> PlanAdvice.Adjustment? in
            guard let change = changes[session.date], let original = originals[session.date], original != session else { return nil }
            return PlanAdvice.Adjustment(original: original, adjusted: session, change: change)
        }
        return PlanAdvice(reasons: adjustments.isEmpty ? [] : reasons, adjustments: adjustments)
    }

    /// El plan con los ajustes aplicados (sin tocar el original).
    public static func apply(_ advice: PlanAdvice, to plan: TrainingPlan) -> TrainingPlan {
        guard !advice.isEmpty else { return plan }
        let byDate = Dictionary(uniqueKeysWithValues: advice.adjustments.map { ($0.original.date, $0.adjusted) })
        var result = plan
        for week in result.weeks.indices {
            for session in result.weeks[week].sessions.indices {
                if let adjusted = byDate[result.weeks[week].sessions[session].date] {
                    result.weeks[week].sessions[session] = adjusted
                }
            }
        }
        return result
    }

    // MARK: Señales

    static func lowRecovery(_ recovery: [(day: Date, value: Int?)], today: Date, calendar: Calendar) -> PlanAdvice.Reason? {
        let todayStart = calendar.startOfDay(for: today)
        let values = recovery.compactMap { item in item.value.map { (calendar.startOfDay(for: item.day), $0) } }
        guard let recentStart = calendar.date(byAdding: .day, value: -2, to: todayStart) else { return nil }
        let recent = values.filter { $0.0 >= recentStart && $0.0 <= todayStart }.map(\.1)
        let previous = values.filter { $0.0 < recentStart }.map { Double($0.1) }
        guard recent.count >= 2 else { return nil }
        let usual = previous.count >= 7 ? RobustBaseline(previous).median : 70
        let threshold = max(50, usual - 15)
        let lowDays = recent.filter { Double($0) < threshold }.count
        guard lowDays >= 2 else { return nil }
        let average = recent.reduce(0, +) / recent.count
        return .lowRecovery(lowDays: lowDays, recent: average, usual: Int(usual.rounded()))
    }

    static func volumeRatio(_ runs: [WorkoutSummary], today: Date, calendar: Calendar) -> Double? {
        let todayStart = calendar.startOfDay(for: today)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
              let previousStart = calendar.date(byAdding: .day, value: -28, to: weekStart) else { return nil }
        let running = runs.filter(\.activity.isRun)
        let last = running.filter { $0.start >= weekStart && $0.start <= today }.compactMap(\.distanceMeters).reduce(0, +)
        let before = running.filter { $0.start >= previousStart && $0.start < weekStart }.compactMap(\.distanceMeters).reduce(0, +) / 4
        guard before >= 10_000 else { return nil }
        return last / before
    }

    static func hardSessions(_ runs: [WorkoutSummary], maxHeartRate: Double?, today: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        guard let start = calendar.date(byAdding: .day, value: -6, to: todayStart) else { return 0 }
        let reference = EffortClassifier.referenceMaxHeartRate(configured: maxHeartRate, runs: runs)
        return runs.filter { $0.activity.isRun && $0.start >= start && $0.start <= today }
            .filter { EffortClassifier.classify($0, maxHeartRate: reference) >= .hard }
            .count
    }
}
