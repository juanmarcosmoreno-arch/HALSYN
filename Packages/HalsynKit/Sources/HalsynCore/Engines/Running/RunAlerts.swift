import Foundation

/// Alertas de ritmo y zona cardíaca durante la carrera (hápticas en el reloj).
public struct RunAlertConfiguration: Hashable, Codable, Sendable {
    public var paceEnabled: Bool
    /// Rango de ritmo para carreras libres. En intervalos manda el objetivo de cada serie.
    public var paceRange: PaceRange
    public var zoneEnabled: Bool
    public var lowestZone: Int
    public var highestZone: Int
    /// Segundos que debe mantenerse fuera de rango antes de avisar (evita avisos por picos).
    public var sustain: TimeInterval
    /// Segundos mínimos entre dos avisos del mismo tipo mientras sigue fuera de rango.
    public var repeatInterval: TimeInterval

    public init(
        paceEnabled: Bool = false,
        paceRange: PaceRange = PaceRange(fastest: 300, slowest: 330),
        zoneEnabled: Bool = false,
        lowestZone: Int = 2,
        highestZone: Int = 3,
        sustain: TimeInterval = 10,
        repeatInterval: TimeInterval = 60
    ) {
        self.paceEnabled = paceEnabled
        self.paceRange = paceRange
        self.zoneEnabled = zoneEnabled
        self.lowestZone = min(max(min(lowestZone, highestZone), 1), 5)
        self.highestZone = min(max(max(lowestZone, highestZone), 1), 5)
        self.sustain = sustain
        self.repeatInterval = repeatInterval
    }

    public var zoneRange: ClosedRange<Int> { min(lowestZone, highestZone)...max(lowestZone, highestZone) }
}

public enum RunAlert: String, Hashable, Sendable {
    case paceTooFast
    case paceTooSlow
    case paceBackInRange
    case heartRateAboveZone
    case heartRateBelowZone
    case heartRateBackInZone

    public var title: String {
        switch self {
        case .paceTooFast: "Más rápido que el objetivo"
        case .paceTooSlow: "Más lento que el objetivo"
        case .paceBackInRange: "Ritmo en rango"
        case .heartRateAboveZone: "Por encima de la zona"
        case .heartRateBelowZone: "Por debajo de la zona"
        case .heartRateBackInZone: "En tu zona"
        }
    }
}

/// Vigila una magnitud respecto a su rango: avisa solo si sale durante
/// `sustain` segundos, repite cada `repeatInterval` y avisa al volver.
struct RangeMonitor: Sendable {
    enum Position: Equatable, Sendable { case below, within, above }

    private var pending: (position: Position, since: Date)?
    private var alerted: (position: Position, at: Date)?

    mutating func reset() {
        pending = nil
        alerted = nil
    }

    /// `position == nil`: sin dato (no cambia el estado de aviso, pero reinicia la espera).
    mutating func update(_ position: Position?, at date: Date, sustain: TimeInterval, repeatInterval: TimeInterval) -> Position? {
        guard let position else {
            pending = nil
            return nil
        }
        if position == .within {
            pending = nil
            if alerted != nil {
                alerted = nil
                return .within
            }
            return nil
        }
        if pending?.position != position {
            pending = (position, date)
        }
        guard let pending, date.timeIntervalSince(pending.since) >= sustain else { return nil }
        if let alerted, alerted.position == position, date.timeIntervalSince(alerted.at) < repeatInterval {
            return nil
        }
        alerted = (position, date)
        return position
    }
}

public struct RunAlertEngine: Sendable {
    /// Margen de vuelta al rango de ritmo (s/km): tras un aviso hay que entrar
    /// claramente en el rango para que cuente como "en rango" (evita avisos alternos en el borde).
    public static let paceHysteresis: Double = 3

    public var configuration: RunAlertConfiguration
    private var pace = RangeMonitor()
    private var zone = RangeMonitor()
    private var lastPaceTarget: PaceRange?
    private var paceAlerting = false

    public init(configuration: RunAlertConfiguration = .init()) {
        self.configuration = configuration
    }

    /// Evalúa el ritmo actual y la zona. `paceTarget` es el objetivo vigente
    /// (el de la serie en intervalos o el de la configuración); `nil` desactiva el aviso de ritmo.
    public mutating func evaluate(pace current: Pace?, paceTarget: PaceRange?, zone currentZone: Int?, at date: Date) -> [RunAlert] {
        var alerts: [RunAlert] = []

        if paceTarget != lastPaceTarget {
            pace.reset()
            paceAlerting = false
            lastPaceTarget = paceTarget
        }
        if let target = paceTarget {
            let position = current.map { Self.position(of: $0.secondsPerKilometer, in: target, alerting: paceAlerting) }
            switch pace.update(position, at: date, sustain: configuration.sustain, repeatInterval: configuration.repeatInterval) {
            case .below?: alerts.append(.paceTooFast); paceAlerting = true
            case .above?: alerts.append(.paceTooSlow); paceAlerting = true
            case .within?: alerts.append(.paceBackInRange); paceAlerting = false
            case nil: break
            }
        }

        if configuration.zoneEnabled {
            let range = configuration.zoneRange
            let position: RangeMonitor.Position? = currentZone.map { $0 < range.lowerBound ? .below : ($0 > range.upperBound ? .above : .within) }
            switch zone.update(position, at: date, sustain: configuration.sustain, repeatInterval: configuration.repeatInterval) {
            case .below?: alerts.append(.heartRateBelowZone)
            case .above?: alerts.append(.heartRateAboveZone)
            case .within?: alerts.append(.heartRateBackInZone)
            case nil: break
            }
        }
        return alerts
    }

    /// Reinicia las esperas (p. ej. al pausar).
    public mutating func reset() {
        pace.reset()
        zone.reset()
        paceAlerting = false
    }

    /// Ritmo menor (en s/km) que el rango = más rápido = `.below`.
    private static func position(of secondsPerKilometer: Double, in range: PaceRange, alerting: Bool) -> RangeMonitor.Position {
        let margin = alerting ? min(paceHysteresis, (range.slowest - range.fastest) / 4) : 0
        if secondsPerKilometer < range.fastest + margin { return .below }
        if secondsPerKilometer > range.slowest - margin { return .above }
        return .within
    }
}
