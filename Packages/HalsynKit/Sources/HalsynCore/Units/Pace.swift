import Foundation

/// Sistema de unidades elegido por el usuario.
public enum UnitSystem: String, CaseIterable, Codable, Identifiable, Sendable {
    case metric
    case imperial

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .metric: "Métrico (km)"
        case .imperial: "Imperial (mi)"
        }
    }

    public var distanceUnitSymbol: String {
        switch self {
        case .metric: "km"
        case .imperial: "mi"
        }
    }

    public var metersPerDistanceUnit: Double {
        switch self {
        case .metric: 1000
        case .imperial: 1609.344
        }
    }

    public var paceUnitSymbol: String { "/\(distanceUnitSymbol)" }
}

/// Ritmo de carrera, almacenado como segundos por kilómetro.
///
/// El cálculo de ritmo instantáneo y suavizado a partir de GPS llega en la
/// Fase 4 (`RUNNING_ENGINE.md`); este tipo solo representa y formatea el valor.
public struct Pace: Hashable, Comparable, Sendable {
    public let secondsPerKilometer: Double

    /// Distancia mínima para calcular un ritmo medio con sentido.
    public static let minimumDistanceMeters: Double = 10

    /// Ritmos más lentos que esto (60 min/km) se consideran parado y no se muestran.
    public static let slowestDisplayableSecondsPerKilometer: Double = 3600

    public init(secondsPerKilometer: Double) {
        self.secondsPerKilometer = secondsPerKilometer
    }

    /// Devuelve `nil` si la distancia o la duración no permiten un ritmo válido.
    public init?(distanceMeters: Double, duration: TimeInterval) {
        guard distanceMeters >= Self.minimumDistanceMeters, duration > 0 else { return nil }
        let value = duration / (distanceMeters / 1000)
        guard value.isFinite, value <= Self.slowestDisplayableSecondsPerKilometer else { return nil }
        secondsPerKilometer = value
    }

    /// Ritmo a partir de velocidad en m/s.
    public init?(metersPerSecond speed: Double) {
        guard speed > 0, speed.isFinite else { return nil }
        let value = 1000 / speed
        guard value <= Self.slowestDisplayableSecondsPerKilometer else { return nil }
        secondsPerKilometer = value
    }

    public func seconds(per unit: UnitSystem) -> Double {
        secondsPerKilometer * unit.metersPerDistanceUnit / 1000
    }

    /// Formato "m:ss" (sin unidad). Redondea al segundo más cercano.
    public func formatted(in unit: UnitSystem = .metric) -> String {
        let total = Int(seconds(per: unit).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func < (lhs: Pace, rhs: Pace) -> Bool {
        // Un ritmo "menor" es más rápido.
        lhs.secondsPerKilometer < rhs.secondsPerKilometer
    }
}

public enum HalsynFormat {
    /// Duración como "h:mm:ss" o "m:ss".
    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Distancia en la unidad elegida, con dos decimales.
    public static func distance(meters: Double, unit: UnitSystem = .metric) -> String {
        String(format: "%.2f", meters / unit.metersPerDistanceUnit)
    }

    /// Horas decimales a "7 h 48 min".
    public static func hoursAndMinutes(_ hours: Double) -> String {
        let totalMinutes = max(0, Int((hours * 60).rounded()))
        return "\(totalMinutes / 60) h \(totalMinutes % 60) min"
    }

    /// Valor de una métrica sin unidad, con la precisión adecuada.
    public static func metricValue(_ value: Double, kind: MetricKind, unit: UnitSystem = .metric) -> String {
        switch kind {
        case .steps, .heartRate, .restingHeartRate, .heartRateVariability, .activeEnergy, .exerciseTime:
            return String(Int(value.rounded()))
        case .walkingRunningDistance:
            return distance(meters: value, unit: unit)
        case .sleepDuration, .vo2Max, .respiratoryRate:
            return String(format: "%.1f", value)
        case .oxygenSaturation:
            return String(Int((value * 100).rounded()))
        }
    }

    /// Unidad mostrada para una métrica según el sistema elegido.
    public static func unitSymbol(for kind: MetricKind, unit: UnitSystem = .metric) -> String {
        kind == .walkingRunningDistance ? unit.distanceUnitSymbol : kind.unit.symbol
    }
}
