import Foundation

/// Lo que el reloj necesita del plan: el objetivo y las sesiones de los
/// próximos días. Viaja con los ajustes de SPRING (el plan completo se queda
/// en el iPhone, que lo reajusta).
public struct PlanSnapshot: Codable, Hashable, Sendable {
    public var distance: RaceDistance
    public var raceDate: Date
    public var goalTime: TimeInterval?
    /// Sesiones desde hoy (incluidos los descansos del plan), ordenadas por fecha.
    public var sessions: [PlannedSession]

    public static let days = 14

    /// Ritmo suave del plan (de un rodaje suave), para calentar y volver a la calma en la cinta.
    public var easyPace: PaceRange? {
        sessions.first { ($0.kind == .easy || $0.kind == .recovery) && $0.pace != nil }?.pace
    }

    public init(distance: RaceDistance, raceDate: Date, goalTime: TimeInterval?, sessions: [PlannedSession]) {
        self.distance = distance
        self.raceDate = raceDate
        self.goalTime = goalTime
        self.sessions = sessions
    }

    /// Copia para el reloj; `today` reemplaza la sesión de hoy (la ya adaptada a
    /// tu recuperación, si cambió).
    public init(plan: TrainingPlan, today: Date, adaptedToday: PlannedSession? = nil, calendar: Calendar) {
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: Self.days, to: start) ?? start
        var sessions = plan.weeks.flatMap(\.sessions).filter { $0.date >= start && $0.date < end }
        if let adaptedToday, let i = sessions.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            sessions[i] = adaptedToday
        }
        self.init(distance: plan.goal.distance, raceDate: plan.goal.raceDate, goalTime: plan.goal.goalTime, sessions: sessions.sorted { $0.date < $1.date })
    }

    /// Sesiones de hoy en adelante (el reloj puede llevar días sin sincronizar).
    public func upcoming(from today: Date, calendar: Calendar) -> [PlannedSession] {
        let start = calendar.startOfDay(for: today)
        return sessions.filter { $0.date >= start }
    }
}

extension SessionKind {
    /// Para qué sirve la sesión y cómo hacerla (pautas habituales de
    /// entrenamiento, Daniels y Seiler).
    public var explanation: String {
        switch self {
        case .easy:
            "A ritmo de conversación: deberías poder hablar en frases. Es la base del plan: mejora tu resistencia aeróbica y te ayuda a recuperar de las sesiones duras. Si dudas, ve más lento."
        case .long:
            "Suave y constante, más larga que el resto. Entrena el cuerpo para aguantar más tiempo; importa el tiempo corriendo, no el ritmo. Lleva agua si dura más de una hora."
        case .tempo:
            "Cómodamente duro: el ritmo que podrías sostener cerca de una hora en carrera. Sube el ritmo que aguantas sin acumular cansancio. Calienta antes y no lo conviertas en una carrera."
        case .intervals:
            "Series rápidas, a ritmo de carrera de 3 a 5 km, con trote suave entre medio. Mejoran tu VO₂ máx. y tu economía de carrera. Todas iguales: la última no debería ser la peor."
        case .recovery:
            "Muy suave y corta, para soltar las piernas después de un día duro. Más lenta que un rodaje suave; si te cuesta, camina."
        case .rest:
            "El cuerpo se adapta al entrenamiento mientras descansa. Puedes caminar o hacer movilidad suave."
        case .test:
            "Un esfuerzo a tope y a ritmo parejo para medir tu forma. Con el resultado se ajustan los ritmos del plan."
        }
    }
}
