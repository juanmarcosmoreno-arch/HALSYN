import Foundation

public enum WorkoutActivity: String, Codable, CaseIterable, Sendable {
    case outdoorRun
    case indoorRun
    case walk
    case other

    public var title: String {
        switch self {
        case .outdoorRun: "Carrera al aire libre"
        case .indoorRun: "Carrera en cinta"
        case .walk: "Caminata"
        case .other: "Entrenamiento"
        }
    }

    public var systemImage: String {
        switch self {
        case .outdoorRun, .indoorRun: "figure.run"
        case .walk: "figure.walk"
        case .other: "figure.mixed.cardio"
        }
    }
}

/// Resumen de un entrenamiento terminado. Los campos opcionales son `nil`
/// cuando el reloj no los midió: nunca se rellenan con estimaciones.
public struct WorkoutSummary: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let activity: WorkoutActivity
    public let start: Date
    public let duration: TimeInterval
    public let distanceMeters: Double?
    public let averageHeartRate: Double?
    public let maxHeartRate: Double?
    public let activeEnergyKilocalories: Double?
    public let averageCadence: Double?
    public let origin: DataOrigin

    public init(
        id: UUID = UUID(),
        activity: WorkoutActivity,
        start: Date,
        duration: TimeInterval,
        distanceMeters: Double?,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        activeEnergyKilocalories: Double?,
        averageCadence: Double?,
        origin: DataOrigin
    ) {
        self.id = id
        self.activity = activity
        self.start = start
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageCadence = averageCadence
        self.origin = origin
    }

    public var end: Date { start.addingTimeInterval(duration) }

    /// Ritmo medio, solo si hay distancia suficiente para que tenga sentido.
    public var averagePace: Pace? {
        guard let distanceMeters else { return nil }
        return Pace(distanceMeters: distanceMeters, duration: duration)
    }
}

/// Objetivo del módulo MÅL. `target` y `current` usan la unidad base de la
/// métrica (`MetricKind.unit`): metros para distancia, horas para sueño, etc.
public struct Goal: Hashable, Identifiable, Sendable {
    public enum Period: String, Sendable {
        case daily, weekly, monthly

        public var title: String {
            switch self {
            case .daily: "Diario"
            case .weekly: "Semanal"
            case .monthly: "Mensual"
            }
        }
    }

    public let id: UUID
    public let title: String
    public let metric: MetricKind
    public let target: Double
    public let current: Double
    public let period: Period
    public let origin: DataOrigin

    public init(id: UUID = UUID(), title: String, metric: MetricKind, target: Double, current: Double, period: Period, origin: DataOrigin) {
        self.id = id
        self.title = title
        self.metric = metric
        self.target = target
        self.current = current
        self.period = period
        self.origin = origin
    }

    /// Progreso 0...1 (se satura en 1).
    public var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    public var isCompleted: Bool { current >= target }
}
