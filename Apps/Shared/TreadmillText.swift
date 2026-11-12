import Foundation
import HalsynCore

/// Textos de la equivalencia en cinta (iPhone y reloj).
enum TreadmillText {
    /// Inclinación elegida para la cinta (por dispositivo).
    static let inclineKey = "halsyn.treadmillIncline"

    static var storedIncline: Double {
        let value = UserDefaults.standard.double(forKey: inclineKey)
        return TreadmillEquivalent.inclines.contains(value) ? value : TreadmillEquivalent.referenceIncline
    }

    static func percent(_ incline: Double) -> String {
        "\(Int((incline * 100).rounded())) %"  // nolocalize
    }

    /// "12.9–13.3 km/h" (o mph).
    static func speed(_ range: ClosedRange<Double>, unit: UnitSystem) -> String {
        let factor = unit == .metric ? 1 : 1 / 1.609344
        let symbol = unit == .metric ? "km/h" : "mph"  // nolocalize
        let low = HalsynFormat.decimal(range.lowerBound * factor, fractionDigits: 1)
        let high = HalsynFormat.decimal(range.upperBound * factor, fractionDigits: 1)
        return low == high ? "\(low) \(symbol)" : "\(low)–\(high) \(symbol)"  // nolocalize
    }

    private static func minutes(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "" }
        let value = String(Int((seconds / 60).rounded()))
        return " " + String(localized: "(≈ \(value) min)")
    }

    /// Una línea por tramo: "Series: 5 × 800 m a 12.9–13.3 km/h".
    static func line(_ step: TreadmillEquivalent.Step, unit: UnitSystem) -> String {
        let speedText = step.speed.map { speed($0, unit: unit) } ?? ""
        let lengthText = step.distance.map { $0 >= 1000 ? SessionText.distance($0, unit: unit) : "\(HalsynFormat.integer($0)) m" } ?? ""  // nolocalize
        switch step.kind {
        case .warmup:
            return String(localized: "Calentamiento: \(lengthText) a \(speedText)") + minutes(step.duration)
        case .work:
            guard !speedText.isEmpty else {
                return String(localized: "Test: \(lengthText) a tope. En cinta la distancia es estimada: para el VDOT, mejor al aire libre.")
            }
            let repeatsText = String(step.repeats)
            return step.repeats > 1
                ? String(localized: "Series: \(repeatsText) × \(lengthText) a \(speedText)")
                : String(localized: "Bloque: \(lengthText) a \(speedText)") + minutes(step.duration)
        case .recovery:
            let repeatsText = String(step.repeats)
            return String(localized: "Entre series: \(repeatsText) × 2 min caminando o trotando muy suave")
        case .cooldown:
            return String(localized: "Vuelta a la calma: \(lengthText) a \(speedText)") + minutes(step.duration)
        case .steady:
            return String(localized: "\(lengthText) a \(speedText)") + minutes(step.duration)
        }
    }

    static let explanation = "Con 1 % de inclinación, la cinta equivale a correr en llano al aire libre (compensa el aire que no hay en la cinta; Jones y Doust, 1996). Con más inclinación, el mismo esfuerzo pide menos velocidad (ecuación de carrera del ACSM): unos 0,4–0,5 km/h menos por cada punto. Es aproximado: si el pulso se dispara, baja la velocidad."
}
