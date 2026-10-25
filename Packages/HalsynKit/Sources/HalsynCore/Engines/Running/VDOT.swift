import Foundation

/// Modelo VDOT de Daniels y Gilbert ("Oxygen Power", 1979; *Daniels' Running
/// Formula*): un "VO₂ máx. efectivo" calculado a partir de una carrera.
///
/// - Coste de oxígeno a una velocidad `v` (m/min):
///   `VO₂ = −4,60 + 0,182258·v + 0,000104·v²`
/// - Fracción del VO₂ máx. que se sostiene durante `t` minutos:
///   `%VO₂máx = 0,8 + 0,1894393·e^(−0,012778·t) + 0,2989558·e^(−0,1932605·t)`
/// - `VDOT = VO₂ / %VO₂máx`.
///
/// Es una estimación del rendimiento, no una medida de laboratorio. Válido
/// para esfuerzos a tope de unos 3,5 min a 5 h.
public enum VDOT {
    /// Ritmos de entrenamiento como fracción del VDOT, ajustados para
    /// reproducir las tablas publicadas (p. ej. VDOT 50: umbral 4:15/km,
    /// series 3:55/km).
    public static let easyFractions: ClosedRange<Double> = 0.62...0.70
    public static let thresholdFraction = 0.88
    public static let intervalFraction = 0.975

    public static let validMinutes: ClosedRange<Double> = 3.5...300

    /// ml/kg/min a una velocidad en m/min.
    public static func oxygenCost(metersPerMinute v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Fracción del VO₂ máx. sostenible durante `minutes`.
    public static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// VDOT de una carrera a tope. `nil` fuera del rango de validez.
    public static func value(distance meters: Double, time seconds: TimeInterval) -> Double? {
        let minutes = seconds / 60
        guard meters > 0, validMinutes.contains(minutes) else { return nil }
        return oxygenCost(metersPerMinute: meters / minutes) / sustainableFraction(minutes: minutes)
    }

    /// Velocidad (m/min) a la que el coste de oxígeno es `vo2`.
    public static func speed(forOxygenCost vo2: Double) -> Double {
        // Raíz positiva de 0,000104·v² + 0,182258·v − (4,60 + VO₂) = 0.
        let a = 0.000104, b = 0.182258, c = -(4.60 + vo2)
        return (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
    }

    /// Ritmo (s/km) a una fracción del VDOT.
    public static func pace(vdot: Double, fraction: Double) -> Pace {
        Pace(secondsPerKilometer: 60_000 / speed(forOxygenCost: vdot * fraction))
    }

    /// Tiempo de carrera previsto para una distancia con un VDOT (bisección).
    public static func raceTime(vdot: Double, distance meters: Double) -> TimeInterval {
        var low = 60.0, high = 6 * 3600.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            let minutes = mid / 60
            let needed = oxygenCost(metersPerMinute: meters / minutes) / sustainableFraction(minutes: minutes)
            // Más tiempo → menos VDOT necesario.
            if needed > vdot { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}

extension TrainingPaces {
    /// Ritmos de Daniels a partir del VDOT actual. El de carrera es el
    /// objetivo si lo hay; si no, el previsto con tu forma actual.
    public static func from(vdot: Double, target: RaceDistance, goalTime: TimeInterval? = nil) -> TrainingPaces {
        let raceTime = goalTime ?? VDOT.raceTime(vdot: vdot, distance: target.rawValue)
        return TrainingPaces(
            easy: PaceRange(
                fastest: VDOT.pace(vdot: vdot, fraction: VDOT.easyFractions.upperBound).secondsPerKilometer,
                slowest: VDOT.pace(vdot: vdot, fraction: VDOT.easyFractions.lowerBound).secondsPerKilometer
            ),
            tempo: PaceRange(center: VDOT.pace(vdot: vdot, fraction: VDOT.thresholdFraction), tolerance: 5),
            interval: PaceRange(center: VDOT.pace(vdot: vdot, fraction: VDOT.intervalFraction), tolerance: 5),
            race: Pace(secondsPerKilometer: raceTime / (target.rawValue / 1000))
        )
    }
}
