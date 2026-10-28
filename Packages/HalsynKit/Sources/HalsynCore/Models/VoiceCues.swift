import Foundation

/// Qué dice la voz durante la carrera o la salida en bici. Las vibraciones del
/// reloj no cambian: esto solo elige qué se habla.
public struct VoiceCueSettings: Hashable, Codable, Sendable {
    /// Aviso en las vueltas automáticas (cada km o milla, o la distancia elegida).
    public var laps: Bool
    /// Cada cuántas vueltas automáticas habla (1 = todas).
    public var lapEvery: Int
    /// Ritmo de la vuelta (en bici, su velocidad).
    public var lapPace: Bool
    /// Ritmo medio desde la salida (en bici, velocidad media).
    public var averagePace: Bool
    public var heartRate: Bool
    /// Tiempo total en movimiento.
    public var elapsedTime: Bool
    /// Series, recuperaciones e "Intervalos completados".
    public var intervals: Bool
    /// Alertas de ritmo y de zona cardíaca.
    public var alerts: Bool

    public static let lapEveryOptions = [1, 2, 3, 5, 10]

    public init(laps: Bool = true, lapEvery: Int = 1, lapPace: Bool = true, averagePace: Bool = false, heartRate: Bool = true, elapsedTime: Bool = false, intervals: Bool = true, alerts: Bool = true) {
        self.laps = laps
        self.lapEvery = max(1, lapEvery)
        self.lapPace = lapPace
        self.averagePace = averagePace
        self.heartRate = heartRate
        self.elapsedTime = elapsedTime
        self.intervals = intervals
        self.alerts = alerts
    }

    /// Las claves que falten (ajustes de una versión anterior) toman su valor por defecto.
    public init(from decoder: Decoder) throws {
        let defaults = VoiceCueSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        laps = try container.decodeIfPresent(Bool.self, forKey: .laps) ?? defaults.laps
        lapEvery = max(1, try container.decodeIfPresent(Int.self, forKey: .lapEvery) ?? defaults.lapEvery)
        lapPace = try container.decodeIfPresent(Bool.self, forKey: .lapPace) ?? defaults.lapPace
        averagePace = try container.decodeIfPresent(Bool.self, forKey: .averagePace) ?? defaults.averagePace
        heartRate = try container.decodeIfPresent(Bool.self, forKey: .heartRate) ?? defaults.heartRate
        elapsedTime = try container.decodeIfPresent(Bool.self, forKey: .elapsedTime) ?? defaults.elapsedTime
        intervals = try container.decodeIfPresent(Bool.self, forKey: .intervals) ?? defaults.intervals
        alerts = try container.decodeIfPresent(Bool.self, forKey: .alerts) ?? defaults.alerts
    }

    /// `ordinal`: número de vuelta automática (1, 2, 3…). Habla en las múltiplos de `lapEvery`.
    public func speaksLap(_ ordinal: Int) -> Bool {
        laps && ordinal > 0 && ordinal % max(1, lapEvery) == 0
    }
}

extension RunSettings {
    /// Qué dice la voz (por defecto, lo de siempre: cada vuelta con ritmo y pulso,
    /// series y alertas).
    public var cues: VoiceCueSettings {
        get { voiceCues ?? VoiceCueSettings() }
        set { voiceCues = newValue }
    }
}
