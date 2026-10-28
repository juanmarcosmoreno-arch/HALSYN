import Foundation
import HalsynCore

/// Frases de los avisos de voz. Las dice el reloj durante la carrera o la
/// salida, y el iPhone las usa para el ejemplo de Ajustes.
enum CoachPhrases {
    /// "5 minutos 12 segundos" (el sintetizador lee mal "5:12").
    static func spoken(_ pace: Pace, unit: UnitSystem) -> String {
        let total = Int(pace.seconds(per: unit).rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(localized: "\(minutes) minutos \(seconds) segundos")
    }

    /// "25 minutos 30 segundos" o "1 hora 5 minutos".
    static func spokenDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours == 1 { return String(localized: "1 hora \(minutes) minutos") }
        if hours > 1 { return String(localized: "\(hours) horas \(minutes) minutos") }
        return String(localized: "\(minutes) minutos \(seconds) segundos")
    }

    /// "Kilómetro 3" o "Milla 3" si se conoce la distancia en unidades enteras;
    /// si no (vueltas de 400 m, por ejemplo), "Vuelta 3".
    static func lapTitle(unitNumber: Int?, lapNumber: Int, unit: UnitSystem) -> String {
        if let number = unitNumber, number > 0 {
            return unit == .imperial ? String(localized: "Milla \(number)") : String(localized: "Kilómetro \(number)")
        }
        let number = lapNumber
        return String(localized: "Vuelta \(number)")
    }

    /// Corriendo: "Kilómetro 3. Ritmo 5 minutos 12 segundos. Pulso 148", con
    /// solo lo que esté elegido en `cues`.
    static func runLap(title: String, lapPace: Pace?, averagePace: Pace?, heartRate: Double?, elapsed: TimeInterval?, unit: UnitSystem, cues: VoiceCueSettings) -> String {
        var parts = [title]
        if cues.lapPace, let lapPace {
            parts.append(String(localized: "Ritmo \(spoken(lapPace, unit: unit))"))
        }
        if cues.averagePace, let averagePace {
            parts.append(String(localized: "Ritmo medio \(spoken(averagePace, unit: unit))"))
        }
        if cues.heartRate, let heartRate {
            let beats = Int(heartRate.rounded())
            parts.append(String(localized: "Pulso \(beats)"))
        }
        if cues.elapsedTime, let elapsed {
            parts.append(String(localized: "Tiempo \(spokenDuration(elapsed))"))
        }
        return parts.joined(separator: ". ")
    }

    /// En bici: "Kilómetro 25. Últimos 5 a 28,1 kilómetros por hora. Pulso 140".
    /// `lapUnits` es el largo de la vuelta en km o mi (0 si no es entero).
    static func rideLap(title: String, lapSpeed: Speed?, lapUnits: Int, averageSpeed: Speed?, heartRate: Double?, elapsed: TimeInterval?, unit: UnitSystem, cues: VoiceCueSettings) -> String {
        var parts = [title]
        if cues.lapPace, let lapSpeed {
            let value = lapSpeed.formatted(in: unit)
            let count = lapUnits
            if count == 1 {
                parts.append(unit == .imperial ? String(localized: "Última milla a \(value) millas por hora") : String(localized: "Último kilómetro a \(value) kilómetros por hora"))
            } else if count > 1 {
                parts.append(unit == .imperial ? String(localized: "Últimas \(count) a \(value) millas por hora") : String(localized: "Últimos \(count) a \(value) kilómetros por hora"))
            } else {
                parts.append(unit == .imperial ? String(localized: "A \(value) millas por hora") : String(localized: "A \(value) kilómetros por hora"))
            }
        }
        if cues.averagePace, let averageSpeed {
            let value = averageSpeed.formatted(in: unit)
            parts.append(unit == .imperial ? String(localized: "Velocidad media \(value) millas por hora") : String(localized: "Velocidad media \(value) kilómetros por hora"))
        }
        if cues.heartRate, let heartRate {
            let beats = Int(heartRate.rounded())
            parts.append(String(localized: "Pulso \(beats)"))
        }
        if cues.elapsedTime, let elapsed {
            parts.append(String(localized: "Tiempo \(spokenDuration(elapsed))"))
        }
        return parts.joined(separator: ". ")
    }

    /// Ejemplo para Ajustes con valores inventados de una carrera tipo.
    static func example(cues: VoiceCueSettings, unit: UnitSystem) -> String {
        guard cues.laps else { return String(localized: "Sin avisos de vueltas: solo series y alertas, si están activadas.") }
        let number = cues.lapEvery
        let title = lapTitle(unitNumber: number, lapNumber: number, unit: unit)
        return runLap(
            title: title,
            lapPace: Pace(secondsPerKilometer: 312),
            averagePace: Pace(secondsPerKilometer: 318),
            heartRate: 148,
            elapsed: Double(number) * 318 * unit.metersPerDistanceUnit / 1000,
            unit: unit,
            cues: cues
        )
    }
}
