import Foundation

/// Distancias de carrera habituales.
public enum RaceDistance: Double, CaseIterable, Identifiable, Sendable {
    case fiveK = 5000
    case tenK = 10000
    case half = 21097.5
    case marathon = 42195

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .fiveK: "5 km"
        case .tenK: "10 km"
        case .half: "Media maratón"
        case .marathon: "Maratón"
        }
    }
}

/// Tiempo estimado para una distancia, con su rango.
public struct RacePrediction: Hashable, Identifiable, Sendable {
    public let distance: RaceDistance
    public let time: TimeInterval
    public let fastest: TimeInterval
    public let slowest: TimeInterval
    /// Carreras en las que se basa.
    public let basedOn: Int
    /// `true` si se extrapola mucho (la carrera más larga es menos de un tercio de la distancia).
    public let isLongExtrapolation: Bool

    public var id: Double { distance.rawValue }
    public var pace: Pace { Pace(secondsPerKilometer: time / (distance.rawValue / 1000)) }
}

/// Predicción con la fórmula de Riegel (T₂ = T₁ · (D₂/D₁)^1,06), a partir de
/// tus mejores carreras recientes.
///
/// - Usa carreras de los últimos 90 días de 3 km o más.
/// - Para cada distancia toma las 3 predicciones más rápidas (tus mejores
///   esfuerzos) y da la mediana; el rango va de la más rápida a la más lenta
///   de esas 3, ampliado un 3 % (5 % si se extrapola mucho) por el error propio
///   de la fórmula.
/// - Los rodajes no son carreras a tope: si casi nunca corres fuerte, la
///   predicción será conservadora. Y supone que entrenas para esa distancia.
public enum RacePredictor {
    public static let exponent = 1.06
    public static let minimumDistance: Double = 3000
    public static let windowDays = 90
    public static let minimumRuns = 3

    public static func riegel(time: TimeInterval, from distance: Double, to target: Double) -> TimeInterval {
        time * pow(target / distance, exponent)
    }

    public static func predictions(from runs: [WorkoutSummary], endingOn end: Date, calendar: Calendar) -> [RacePrediction] {
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else { return [] }
        let recent = runs.filter { run in
            run.activity.isRun && run.start >= start && run.start <= end
                && (run.distanceMeters ?? 0) >= minimumDistance && run.averagePace != nil
        }
        guard recent.count >= minimumRuns, let longest = recent.compactMap(\.distanceMeters).max() else { return [] }
        return RaceDistance.allCases.compactMap { target in
            let estimates = recent.compactMap { run -> TimeInterval? in
                guard let distance = run.distanceMeters else { return nil }
                return riegel(time: run.duration, from: distance, to: target.rawValue)
            }.sorted()
            let best = Array(estimates.prefix(3))
            guard best.count == 3 else { return nil }
            let isLong = longest < target.rawValue / 3
            let margin = isLong ? 0.05 : 0.03
            return RacePrediction(
                distance: target,
                time: best[1],
                fastest: best[0] * (1 - margin),
                slowest: best[2] * (1 + margin),
                basedOn: recent.count,
                isLongExtrapolation: isLong
            )
        }
    }
}
