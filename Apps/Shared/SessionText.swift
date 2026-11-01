import HalsynCore
import Foundation

/// Textos de sesiones.
enum SessionText {
    static func distance(_ meters: Double, unit: UnitSystem) -> String {
        "\(HalsynFormat.decimal(meters / unit.metersPerDistanceUnit, fractionDigits: 1)) \(unit.distanceUnitSymbol)"
    }

    /// "6 × 800 m a 4:43–4:53 /km" o "8,0 km a 6:00–6:30 /km".
    static func detail(_ session: PlannedSession, unit: UnitSystem) -> String {
        let pace = session.pace.map { "\($0.formatted(in: unit)) \(unit.paceUnitSymbol)" } ?? ""
        switch session.kind {
        case .rest:
            return String(localized: "Descanso o paseo suave")
        case .intervals:
            let repeats = session.repeats ?? 0
            let length = HalsynFormat.integer(session.repeatDistance ?? 0)
            return String(localized: "\(repeats) × \(length) m a \(pace), con 2 min de trote entre series")
        case .tempo:
            let block = distance(session.repeatDistance ?? 0, unit: unit)
            return String(localized: "\(block) continuos a \(pace), con calentamiento y vuelta a la calma")
        case .test:
            let length = distance(session.repeatDistance ?? 0, unit: unit)
            return String(localized: "Calienta 10–15 min suave sin grabar y haz 3 o 4 aceleraciones. Luego inicia el test en el reloj y corre \(length) a tope, a ritmo parejo. Cuando el reloj diga «Intervalos completados», detén el entrenamiento enseguida.")
        default:
            return String(localized: "\(distance(session.distance, unit: unit)) a \(pace)")
        }
    }
}
