import Foundation

/// Qué mide un objetivo de MÅL.
public enum GoalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case steps
    case exerciseMinutes
    case distance
    case runningDistance
    case runs
    case sleepAverage
    case activeEnergy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .steps: "Pasos"
        case .exerciseMinutes: "Minutos de ejercicio"
        case .distance: "Distancia caminando y corriendo"
        case .runningDistance: "Distancia corriendo"
        case .runs: "Número de carreras"
        case .sleepAverage: "Sueño medio por noche"
        case .activeEnergy: "Energía activa"
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: "shoeprints.fill"
        case .exerciseMinutes: "figure.mixed.cardio"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .runningDistance, .runs: "figure.run"
        case .sleepAverage: "moon"
        case .activeEnergy: "flame"
        }
    }

    /// Métrica diaria de la que sale el progreso (`nil` = se calcula con entrenamientos).
    public var metric: MetricKind? {
        switch self {
        case .steps: .steps
        case .exerciseMinutes: .exerciseTime
        case .distance: .walkingRunningDistance
        case .sleepAverage: .sleepDuration
        case .activeEnergy: .activeEnergy
        case .runningDistance, .runs: nil
        }
    }

    /// `true` si el progreso es una media (sueño) y no una suma.
    public var isAverage: Bool { self == .sleepAverage }

    /// Unidad base del objetivo: la de la métrica; metros para distancia corriendo; carreras.
    public var baseUnitSymbol: String {
        switch self {
        case .runningDistance: "m"
        case .runs: ""
        default: metric?.unit.symbol ?? ""
        }
    }

    public var allowedPeriods: [Goal.Period] {
        switch self {
        case .sleepAverage: [.daily, .weekly]
        case .runs: [.weekly, .monthly]
        case .runningDistance: [.weekly, .monthly]
        default: [.daily, .weekly, .monthly]
        }
    }
}

/// Recordatorio opcional de un objetivo (notificación local, sin datos de salud).
public struct GoalReminder: Hashable, Codable, Sendable {
    /// Días de la semana (`Calendar.weekday`, 1 = domingo). Vacío = todos.
    public var weekdays: Set<Int>
    /// Minutos desde medianoche.
    public var minutes: Int

    public init(weekdays: Set<Int> = [], minutes: Int = 19 * 60) {
        self.weekdays = weekdays
        self.minutes = min(max(minutes, 0), 24 * 60 - 1)
    }
}

/// Aumento gradual del objetivo semanal de distancia corriendo.
/// Se sube como mucho un 10 % por semana (pauta conservadora habitual; no
/// garantiza evitar lesiones) desde `start` hasta `end`.
public struct GoalProgression: Hashable, Codable, Sendable {
    public static let maximumWeeklyIncrease = 0.10

    public var startValue: Double
    public var endValue: Double
    public var startDate: Date

    public init(startValue: Double, endValue: Double, startDate: Date) {
        self.startValue = startValue
        self.endValue = endValue
        self.startDate = startDate
    }

    /// Objetivo de la semana `week` (0 = primera). Crece ×1,10 por semana sin pasar de `endValue`.
    public func target(week: Int) -> Double {
        guard startValue > 0, endValue > startValue else { return max(endValue, startValue) }
        return min(endValue, startValue * pow(1 + Self.maximumWeeklyIncrease, Double(max(week, 0))))
    }

    /// Semanas necesarias para llegar al final.
    public var weeksToReachEnd: Int {
        guard startValue > 0, endValue > startValue else { return 0 }
        return Int(ceil(log(endValue / startValue) / log(1 + Self.maximumWeeklyIncrease)))
    }
}

/// Objetivo creado por el usuario. Se guarda solo en el dispositivo.
public struct GoalDefinition: Hashable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var kind: GoalKind
    public var period: Goal.Period
    /// En la unidad base (metros, minutos, horas, pasos, kcal, número de carreras).
    public var target: Double
    public var reminder: GoalReminder?
    public var progression: GoalProgression?
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: GoalKind, period: Goal.Period, target: Double, reminder: GoalReminder? = nil, progression: GoalProgression? = nil, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.period = kind.allowedPeriods.contains(period) ? period : (kind.allowedPeriods.first ?? .weekly)
        self.target = max(target, 0)
        self.reminder = reminder
        self.progression = kind == .runningDistance && period == .weekly ? progression : nil
        self.createdAt = createdAt
    }

    /// Objetivo vigente en la fecha (con progresión, el de esa semana).
    public func target(on date: Date, calendar: Calendar) -> Double {
        guard let progression else { return target }
        let start = calendar.dateInterval(of: .weekOfYear, for: progression.startDate)?.start ?? progression.startDate
        let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let weeks = calendar.dateComponents([.weekOfYear], from: start, to: current).weekOfYear ?? 0
        return progression.target(week: weeks)
    }

    /// Plantillas con referencias públicas cuando las hay (ver SCIENTIFIC_REFERENCES.md).
    public static let templates: [GoalDefinition] = [
        // OMS: 150–300 min semanales de actividad moderada.
        GoalDefinition(kind: .exerciseMinutes, period: .weekly, target: 150),
        GoalDefinition(kind: .steps, period: .daily, target: 8000),
        // Recomendación general para adultos: 7–9 h.
        GoalDefinition(kind: .sleepAverage, period: .weekly, target: 7),
        GoalDefinition(kind: .runs, period: .weekly, target: 3),
        GoalDefinition(kind: .runningDistance, period: .weekly, target: 20_000),
    ]
}

/// Persistencia de los objetivos (JSON en `UserDefaults`, solo en el dispositivo).
public enum GoalStorage {
    public static let key = "halsyn.mal.goals"

    public static func load(from defaults: UserDefaults) -> [GoalDefinition] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([GoalDefinition].self, from: data)) ?? []
    }

    public static func save(_ goals: [GoalDefinition], to defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(goals) {
            defaults.set(data, forKey: key)
        }
    }
}
