import Foundation

/// Datos de la carrera en curso que el reloj manda al iPhone (sesión espejo
/// de HealthKit) para mostrarla en la pantalla bloqueada (Live Activity).
public struct RunLiveUpdate: Codable, Hashable, Sendable {
    public enum Activity: String, Codable, Hashable, Sendable {
        case run, walk, ride
    }

    public var activity: Activity
    /// Tiempo en movimiento (sin pausas) en el momento `sent`.
    public var elapsed: TimeInterval
    public var isPaused: Bool
    /// Metros.
    public var distance: Double
    /// Ritmo actual en s/km.
    public var pace: Double?
    public var heartRate: Double?
    /// Paso del plan, p. ej. "SERIE 2/6".
    public var step: String?
    /// Ritmo objetivo (s/km), si el paso lo tiene.
    public var paceFastest: Double?
    public var paceSlowest: Double?
    public var metric: Bool
    public var sent: Date

    public init(activity: Activity, elapsed: TimeInterval, isPaused: Bool, distance: Double, pace: Double? = nil, heartRate: Double? = nil, step: String? = nil, paceFastest: Double? = nil, paceSlowest: Double? = nil, metric: Bool = true, sent: Date = .now) {
        self.activity = activity
        self.elapsed = elapsed
        self.isPaused = isPaused
        self.distance = distance
        self.pace = pace
        self.heartRate = heartRate
        self.step = step
        self.paceFastest = paceFastest
        self.paceSlowest = paceSlowest
        self.metric = metric
        self.sent = sent
    }

    /// Momento desde el que cuenta el cronómetro (descontadas las pausas).
    public var timerStart: Date { sent.addingTimeInterval(-elapsed) }

    public var paceTarget: PaceRange? {
        guard let paceFastest, let paceSlowest else { return nil }
        return PaceRange(fastest: paceFastest, slowest: paceSlowest)
    }

    public var paceStatus: PaceRange.Status? {
        guard let target = paceTarget, let pace else { return nil }
        return target.status(of: Pace(secondsPerKilometer: pace))
    }
}
