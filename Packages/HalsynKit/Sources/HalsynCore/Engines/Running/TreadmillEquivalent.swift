import Foundation

/// Equivalencia entre un ritmo al aire libre y la velocidad e inclinación de una cinta.
///
/// - **1 % de inclinación ≈ correr en llano al aire libre** (Jones & Doust,
///   *J Sports Sci* 1996): compensa la falta de resistencia del aire. Lo
///   midieron entre 2:51 y 4:43 min/km; a ritmos más lentos el aire pesa menos
///   y el 1 % queda algo más exigente que la calle (aproximación prudente).
/// - **Más inclinación, menos velocidad** para el mismo esfuerzo, con la
///   ecuación de carrera del ACSM (*Guidelines for Exercise Testing and
///   Prescription*): coste de O₂ por metro ∝ 0,2 + 0,9 × pendiente. Cada punto de
///   inclinación por encima del 1 % baja la velocidad equivalente un 4–5 %.
/// - Las velocidades se redondean a 0,1 km/h, el paso de casi todas las cintas.
/// - Es una equivalencia de esfuerzo aproximada: la cinta no reproduce curvas,
///   viento ni bajadas. Para las series cortas, mejor guiarse también por el pulso.
public enum TreadmillEquivalent {
    public static let referenceIncline = 0.01
    /// Inclinaciones que se ofrecen (1 %, 2 %, 3 %).
    public static let inclines: [Double] = [0.01, 0.02, 0.03]
    /// Velocidad máxima de una cinta doméstica habitual (km/h).
    public static let typicalMaximumSpeed = 18.0

    /// km/h en la cinta, con la inclinación dada (fracción), equivalente a un
    /// ritmo al aire libre en llano (s/km).
    public static func speed(outdoorPace secondsPerKilometer: Double, incline: Double = referenceIncline) -> Double {
        guard secondsPerKilometer > 0 else { return 0 }
        let outdoor = 3600 / secondsPerKilometer
        let factor = 0.2 / (0.2 + 0.9 * (incline - referenceIncline))
        return (outdoor * factor * 10).rounded() / 10
    }

    /// Rango de velocidades para un rango de ritmos (el ritmo más rápido da la velocidad más alta).
    public static func speedRange(_ pace: PaceRange, incline: Double = referenceIncline) -> ClosedRange<Double> {
        speed(outdoorPace: pace.slowest, incline: incline)...speed(outdoorPace: pace.fastest, incline: incline)
    }

    /// Un tramo de la sesión en la cinta.
    public struct Step: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable {
            case warmup, work, recovery, cooldown, steady
        }

        public let kind: Kind
        /// Metros del tramo (o `nil` si va por tiempo).
        public let distance: Double?
        /// Segundos del tramo (recuperaciones por tiempo, o lo aproximado a esa velocidad).
        public let duration: TimeInterval?
        /// Velocidad en km/h (`nil` en recuperaciones caminando o trotando a gusto).
        public let speed: ClosedRange<Double>?
        public let incline: Double
        /// Veces que se repite (series).
        public let repeats: Int
    }

    /// Guía de la sesión en la cinta. `easyPace`: tu ritmo suave (calentamiento y calma).
    public static func guide(for session: PlannedSession, easyPace: PaceRange?, incline: Double = referenceIncline) -> [Step] {
        let easy = easyPace.map { speedRange($0, incline: incline) }
        func time(_ meters: Double, _ range: ClosedRange<Double>?) -> TimeInterval? {
            guard let range else { return nil }
            let mid = (range.lowerBound + range.upperBound) / 2
            return mid > 0 ? meters / (mid / 3.6) : nil
        }
        func steady() -> [Step] {
            let range = (session.pace ?? easyPace).map { speedRange($0, incline: incline) }
            return [Step(kind: .steady, distance: session.distance, duration: time(session.distance, range), speed: range, incline: incline, repeats: 1)]
        }
        switch session.kind {
        case .rest:
            return []
        case .intervals, .tempo:
            guard let repeats = session.repeats, let length = session.repeatDistance else { return steady() }
            let work = session.pace.map { speedRange($0, incline: incline) }
            var steps = [Step(kind: .warmup, distance: 2000, duration: time(2000, easy), speed: easy, incline: incline, repeats: 1)]
            steps.append(Step(kind: .work, distance: length, duration: time(length, work), speed: work, incline: incline, repeats: repeats))
            if session.kind == .intervals, repeats > 1 {
                steps.append(Step(kind: .recovery, distance: nil, duration: 120, speed: nil, incline: incline, repeats: repeats - 1))
            }
            steps.append(Step(kind: .cooldown, distance: 2000, duration: time(2000, easy), speed: easy, incline: incline, repeats: 1))
            return steps
        case .test:
            let length = session.repeatDistance ?? session.distance
            return [Step(kind: .work, distance: length, duration: nil, speed: nil, incline: incline, repeats: 1)]
        default:
            return steady()
        }
    }

    /// Velocidad objetivo en la cinta para el ritmo objetivo de un tramo (para el reloj).
    public static func target(_ pace: PaceRange?, incline: Double = referenceIncline) -> ClosedRange<Double>? {
        pace.map { speedRange($0, incline: incline) }
    }
}
