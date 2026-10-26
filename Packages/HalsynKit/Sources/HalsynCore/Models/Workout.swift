import Foundation

public enum WorkoutActivity: String, Codable, CaseIterable, Sendable {
    case outdoorRun
    case indoorRun
    case walk
    case outdoorRide
    case indoorRide
    case other

    public var title: String {
        switch self {
        case .outdoorRun: "Carrera al aire libre"
        case .indoorRun: "Carrera en cinta"
        case .walk: "Caminata"
        case .outdoorRide: "Bici al aire libre"
        case .indoorRide: "Bici en interior"
        case .other: "Entrenamiento"
        }
    }

    public var isRun: Bool { self == .outdoorRun || self == .indoorRun }

    /// Salida en bici (CYKEL), en exterior o en rodillo.
    public var isRide: Bool { self == .outdoorRide || self == .indoorRide }

    public var isIndoor: Bool { self == .indoorRun || self == .indoorRide }

    public var sport: WorkoutSport {
        switch self {
        case .outdoorRun, .indoorRun: .running
        case .walk: .walking
        case .outdoorRide, .indoorRide: .cycling
        case .other: .other
        }
    }

    public var systemImage: String {
        switch self {
        case .outdoorRun, .indoorRun: "figure.run"
        case .walk: "figure.walk"
        case .outdoorRide: "figure.outdoor.cycle"
        case .indoorRide: "figure.indoor.cycle"
        case .other: "figure.mixed.cardio"
        }
    }
}

/// Deporte de un entrenamiento: separa las estadísticas de SPRING (correr) y
/// de CYKEL (bici).
public enum WorkoutSport: String, Codable, CaseIterable, Sendable {
    case running
    case walking
    case cycling
    case other
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
    /// Pasos por minuto corriendo; pedaladas por minuto (rpm) en bici.
    public let averageCadence: Double?
    public let origin: DataOrigin
    /// Potencia media en vatios, si un medidor la registró.
    public let averagePower: Double?
    /// Desnivel positivo en metros, si el entrenamiento lo guardó.
    public let elevationGain: Double?
    /// Hora real de fin (con las pausas). `duration` es solo el tiempo activo.
    public let endDate: Date?

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
        origin: DataOrigin,
        averagePower: Double? = nil,
        elevationGain: Double? = nil,
        endDate: Date? = nil
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
        self.averagePower = averagePower
        self.elevationGain = elevationGain
        self.endDate = endDate
    }

    /// Inicio + tiempo activo (sin pausas).
    public var end: Date { start.addingTimeInterval(duration) }

    /// Fin real con las pausas, para leer las muestras de todo el entrenamiento.
    public var wallClockEnd: Date { max(endDate ?? end, end) }

    /// Ritmo medio, solo si hay distancia suficiente para que tenga sentido.
    public var averagePace: Pace? {
        guard let distanceMeters else { return nil }
        return Pace(distanceMeters: distanceMeters, duration: duration)
    }

    /// Velocidad media (distancia / tiempo), la referencia en bici.
    public var averageSpeed: Speed? {
        guard let distanceMeters else { return nil }
        return Speed(distanceMeters: distanceMeters, duration: duration)
    }
}

/// Objetivo del módulo MÅL. `target` y `current` usan la unidad base de la
/// métrica (`MetricKind.unit`): metros para distancia, horas para sueño, etc.
public struct Goal: Hashable, Identifiable, Sendable {
    public enum Period: String, Codable, CaseIterable, Identifiable, Sendable {
        public var id: String { rawValue }

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
