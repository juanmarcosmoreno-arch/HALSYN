import Foundation

/// Un pico de FC de un entrenamiento, con su estado en la validación.
public struct MaxHeartRatePeak: Hashable, Identifiable, Sendable {
    public enum Status: String, Hashable, Sendable {
        /// Repetido (±1 lpm) en al menos otra sesión: sustenta la FC validada.
        case supported
        /// Más alto que cualquier otra sesión: un pico aislado no basta.
        case isolated
        /// El valor máximo de Salud no se sostiene ni 15 s en las muestras: artefacto probable.
        case transient
        /// Pico muy por encima de la media de la sesión sin muestras que lo confirmen.
        case implausibleGap
        /// Más antiguo que la ventana (12 meses).
        case old
        /// Por debajo de la validada (no la determina).
        case below
    }

    public let id: UUID
    public let date: Date
    /// Lo que Salud guardó como máximo de la sesión.
    public let reported: Double
    /// Pico sostenido ≥ 15 s en las muestras (si las hay).
    public let sustained: Double?
    public let isIndoor: Bool
    public let status: Status

    /// El valor que cuenta de esta sesión: el sostenido si hay muestras.
    public var value: Double { sustained ?? reported }
}

/// FC máxima configurada, registrada y validada, con lo que la sustenta.
public struct MaxHeartRateAssessment: Hashable, Sendable {
    /// La más alta presente en Salud (carreras sin duplicados, valores plausibles).
    public let recorded: Double?
    /// La validada: el valor más alto alcanzado en al menos dos sesiones distintas.
    public let validated: Double?
    /// Solo hay una sesión utilizable: la validada es provisional.
    public let isProvisional: Bool
    /// Picos de cada sesión, de mayor a menor.
    public let peaks: [MaxHeartRatePeak]

    public var supporting: [MaxHeartRatePeak] { peaks.filter { $0.status == .supported } }
}

/// Validación de la FC máxima con tus propios entrenamientos.
///
/// Reglas (RUNNING_ENGINE.md, «FC máxima»):
/// - Carreras sin duplicados ni pulso inválido, de los últimos 12 meses, en
///   cinta o al aire libre (ninguna se excluye por el lugar).
/// - Con muestras: el pico de una sesión es el valor sostenido al menos 15 s;
///   si el máximo de Salud supera ese valor en más de 3 lpm, era un artefacto.
///   Sin muestras: el máximo de Salud, salvo que supere la FC media en más de
///   50 lpm en una carrera de 10 min o más (pico sin confirmación).
/// - **Validada**: el valor más alto alcanzado (±1 lpm) en **al menos dos
///   sesiones distintas**. Un pico aislado puede ser real, pero no basta para
///   fijar las zonas. Con una sola sesión, su pico, marcado como provisional.
/// - No se estima por edad.
public enum MaxHeartRateValidator {
    public static let windowDays = 365
    public static let sustainSeconds: TimeInterval = 15
    public static let transientMargin = 3.0
    public static let maximumGapToAverage = 50.0
    public static let repeatTolerance = 1.0

    /// - `usesWindow`: `false` para no descartar por antigüedad (resultado
    ///   independiente de la fecha del cálculo).
    public static func assess(runs allRuns: [WorkoutSummary], samples: [UUID: [HeartRatePoint]] = [:], today: Date, calendar: Calendar, usesWindow: Bool = true) -> MaxHeartRateAssessment {
        let runs = allRuns.filter(\.activity.isRun)
        let quality = DataQuality.assess(runs)
        let usable = runs.filter { run in
            guard quality[run.id]?.level != .excluded, quality[run.id]?.heartRateUsable != false,
                  let maximum = run.maxHeartRate else { return false }
            return HeartRateZoneConfiguration.plausibleMaxRange.contains(maximum)
        }
        let recorded = usable.compactMap(\.maxHeartRate).max()
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: today)) ?? today

        var peaks: [MaxHeartRatePeak] = []
        for run in usable {
            guard let reported = run.maxHeartRate else { continue }
            let sustained = samples[run.id].flatMap(sustainedPeak)
            var status: MaxHeartRatePeak.Status = .below
            if usesWindow, run.start < windowStart {
                status = .old
            } else if let sustained, reported - sustained > transientMargin {
                status = .transient
            } else if sustained == nil, let average = run.averageHeartRate, run.duration >= 600, reported - average > maximumGapToAverage {
                status = .implausibleGap
            }
            peaks.append(MaxHeartRatePeak(id: run.id, date: run.start, reported: reported, sustained: sustained, isIndoor: run.activity.isIndoor, status: status))
        }

        // Candidatos: dentro de la ventana y sin artefactos.
        let candidates = peaks.filter { $0.status == .below }.sorted { $0.value > $1.value }
        var validated: Double?
        var provisional = false
        for (index, peak) in candidates.enumerated() {
            let repeated = candidates.enumerated().contains { other in
                other.offset != index && other.element.value >= peak.value - repeatTolerance
            }
            if repeated {
                validated = peak.value
                break
            }
        }
        if validated == nil, let only = candidates.first {
            validated = only.value
            provisional = true
        }
        let resolved: [MaxHeartRatePeak] = peaks.map { peak in
            guard peak.status == .below, let validated else { return peak }
            let status: MaxHeartRatePeak.Status = peak.value > validated + repeatTolerance ? .isolated
                : (peak.value >= validated - repeatTolerance ? .supported : .below)
            return MaxHeartRatePeak(id: peak.id, date: peak.date, reported: peak.reported, sustained: peak.sustained, isIndoor: peak.isIndoor, status: status)
        }
        return MaxHeartRateAssessment(recorded: recorded, validated: validated, isProvisional: provisional, peaks: resolved.sorted { $0.value > $1.value })
    }

    /// Valor más alto mantenido al menos 15 s: máximo del mínimo de cada
    /// ventana de 15 s (necesita al menos dos muestras en la ventana).
    public static func sustainedPeak(_ samples: [HeartRatePoint]) -> Double? {
        let sorted = samples.filter { $0.bpm > 0 }.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return nil }
        var best: Double?
        var startIndex = 0
        for endIndex in sorted.indices {
            while sorted[endIndex].date.timeIntervalSince(sorted[startIndex].date) > sustainSeconds { startIndex += 1 }
            guard endIndex > startIndex, sorted[endIndex].date.timeIntervalSince(sorted[startIndex].date) >= sustainSeconds * 0.6 else { continue }
            let low = sorted[startIndex...endIndex].map(\.bpm).min() ?? 0
            best = Swift.max(best ?? low, low)
        }
        return best
    }
}
