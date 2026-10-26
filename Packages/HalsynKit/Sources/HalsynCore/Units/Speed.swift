import Foundation

/// Velocidad, almacenada en metros por segundo. En bici se muestra en km/h o
/// mph (en carrera manda el ritmo, `Pace`).
public struct Speed: Hashable, Comparable, Codable, Sendable {
    public let metersPerSecond: Double

    /// Distancia mínima para calcular una velocidad media con sentido.
    public static let minimumDistanceMeters: Double = 10
    /// Por debajo de 1 km/h se considera parado.
    public static let slowestDisplayableMetersPerSecond: Double = 1000 / 3600.0

    public init(metersPerSecond: Double) {
        self.metersPerSecond = metersPerSecond
    }

    /// Devuelve `nil` si la distancia o la duración no permiten una velocidad válida.
    public init?(distanceMeters: Double, duration: TimeInterval) {
        guard distanceMeters >= Self.minimumDistanceMeters, duration > 0 else { return nil }
        let value = distanceMeters / duration
        guard value.isFinite, value >= Self.slowestDisplayableMetersPerSecond else { return nil }
        metersPerSecond = value
    }

    /// La misma magnitud que un ritmo (s/km).
    public init?(pace: Pace?) {
        guard let pace, pace.secondsPerKilometer > 0 else { return nil }
        self.init(metersPerSecond: 1000 / pace.secondsPerKilometer)
    }

    /// Kilómetros o millas por hora.
    public func value(in unit: UnitSystem) -> Double {
        metersPerSecond * 3600 / unit.metersPerDistanceUnit
    }

    /// Un decimal ("27,4" en español, "27.4" en inglés).
    public func formatted(in unit: UnitSystem = .metric, locale: Locale = .current) -> String {
        HalsynFormat.decimal(value(in: unit), fractionDigits: 1, locale: locale)
    }

    public static func < (lhs: Speed, rhs: Speed) -> Bool {
        lhs.metersPerSecond < rhs.metersPerSecond
    }
}

extension UnitSystem {
    /// "km/h" o "mph".
    public var speedUnitSymbol: String {
        switch self {
        case .metric: "km/h"
        case .imperial: "mph"
        }
    }
}
