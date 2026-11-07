import Foundation

/// Una prueba que informa sobre tu forma: un test, una competición o un
/// entrenamiento con esfuerzo comparable a una prueba.
public struct PerformanceEvidence: Hashable, Identifiable, Sendable {
    public enum Kind: Int, Hashable, Sendable {
        case trainingEffort, test, race
    }

    public let id: UUID
    public let date: Date
    public let distance: Double
    public let time: TimeInterval
    public let kind: Kind
    public let vdot: Double
    /// Peso final en el modelo (0…1): tipo × antigüedad × coherencia.
    public let weight: Double
    /// Se aparta mucho de la tendencia de las demás (se le baja el peso).
    public let isInconsistent: Bool
}

/// Predicción de una distancia por los dos métodos y su combinación.
public struct DistancePrediction: Hashable, Identifiable, Sendable {
    public let distance: Double
    /// Combinación de los dos métodos (media geométrica).
    public let time: TimeInterval
    /// Daniels: VDOT actual (con tendencia) → tiempo.
    public let vdotTime: TimeInterval
    /// Riegel: cada prueba proyectada a esta distancia, ponderada.
    public let riegelTime: TimeInterval
    /// Intervalo del 80 % (solo con datos suficientes).
    public let range: ClosedRange<TimeInterval>?

    public var id: Double { distance }
    public var pace: Pace { Pace(secondsPerKilometer: time / (distance / 1000)) }
    /// Diferencia entre métodos, en fracción del tiempo.
    public var methodGap: Double { abs(vdotTime - riegelTime) / max(time, 1) }
}

/// Estado de tu rendimiento: forma actual, tendencia, confianza y predicciones.
public struct PerformanceAssessment: Hashable, Sendable {
    public enum Confidence: Int, Comparable, Hashable, Sendable {
        case low, medium, high
        public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let evidence: [PerformanceEvidence]
    /// VDOT de hoy (con la tendencia aplicada a las pruebas antiguas).
    public let currentVDOT: Double
    /// Desviación de la estimación en puntos de VDOT.
    public let uncertainty: Double
    /// Cambio de VDOT por semana (Theil–Sen), si hay datos para estimarla.
    public let weeklyTrend: Double?
    public let confidence: Confidence
    public let riegelExponent: Double
    /// Exponente de Riegel ajustado a tus pruebas, si se pudo estimar.
    public let personalExponent: Double?
    /// Hay datos suficientes para dar un intervalo.
    public let hasInterval: Bool

    public func predict(_ distance: Double) -> DistancePrediction {
        let vdotTime = VDOT.raceTime(vdot: currentVDOT, distance: distance)
        let riegelTime = RacePerformanceModel.riegelTime(evidence: evidence, to: distance, exponent: personalExponent ?? riegelExponent) ?? vdotTime
        let combined = (vdotTime * riegelTime).squareRoot()
        var range: ClosedRange<TimeInterval>?
        if hasInterval {
            // ±1,28 σ (80 %) en VDOT, más la mitad del desacuerdo entre métodos.
            let fast = VDOT.raceTime(vdot: currentVDOT + 1.28 * uncertainty, distance: distance)
            let slow = VDOT.raceTime(vdot: max(currentVDOT - 1.28 * uncertainty, 15), distance: distance)
            let spread = abs(vdotTime - riegelTime) / 2
            range = min(fast, combined - spread)...max(slow, combined + spread)
        }
        return DistancePrediction(distance: distance, time: combined, vdotTime: vdotTime, riegelTime: riegelTime, range: range)
    }
}

/// Modelo de rendimiento: une VDOT (Daniels) y Riegel con varias pruebas.
///
/// Reglas (RUNNING_ENGINE.md, "Modelo de rendimiento"):
/// - **Pruebas**: tests y competiciones registrados (últimos 180 días) y
///   esfuerzos de entrenamiento comparables a una prueba (`FitnessEstimator.
///   trainingEfforts`, últimos 42 días, ya filtrados por calidad).
/// - **Peso**: tipo (competición 1, test 0,9, entrenamiento 0,5) ×
///   antigüedad (se reduce a la mitad cada 42 días).
/// - **Tendencia**: pendiente de Theil–Sen del VDOT en el tiempo (mediana de
///   las pendientes entre pares, robusta a un dato raro), con ≥ 3 pruebas en
///   ≥ 21 días; acotada a ±0,25 VDOT/semana.
/// - **VDOT actual**: media ponderada de cada prueba llevada a hoy con la tendencia.
/// - **Incoherencia**: una prueba a más de 3 puntos de la tendencia pesa ×0,25.
/// - **Incertidumbre**: dispersión ponderada de las pruebas alrededor de la
///   tendencia (mínimo 0,8 puntos) + 0,5 si la última prueba tiene más de
///   6 semanas o sale solo de entrenamientos.
/// - **Riegel**: T₂ = T₁·(D₂/D₁)^k, k configurable (1,06 por defecto). Con dos
///   pruebas oficiales a distancias que difieran ×1,5 o más, se estima tu k
///   (mediana de los pares, solo si queda entre 1,01 y 1,15).
/// - **Intervalo** (80 %): solo con 3 pruebas o más.
public enum RacePerformanceModel {
    public static let resultWindowDays = 180
    public static let halfLifeDays = 42.0
    public static let maximumWeeklyTrend = 0.25
    public static let inconsistencyLimit = 3.0
    public static let minimumUncertainty = 0.8
    public static let defaultRiegelExponent = 1.06
    public static let plausibleExponent: ClosedRange<Double> = 1.01...1.15

    public static func assess(results: [PerformanceResult], runs: [WorkoutSummary], maxHeartRate: Double? = nil, riegelExponent: Double = defaultRiegelExponent, today: Date, calendar: Calendar) -> PerformanceAssessment? {
        let todayStart = calendar.startOfDay(for: today)
        func ageDays(_ date: Date) -> Double {
            Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: todayStart).day ?? 0)
        }

        // 1. Pruebas con su peso por tipo y antigüedad.
        var raw: [(id: UUID, date: Date, distance: Double, time: TimeInterval, kind: PerformanceEvidence.Kind, vdot: Double, base: Double)] = []
        let markedWorkouts = Set(results.compactMap(\.workoutID))
        for result in results where result.date <= today && ageDays(result.date) <= Double(resultWindowDays) {
            guard let vdot = result.vdot else { continue }
            let kind: PerformanceEvidence.Kind = result.kind == .race ? .race : .test
            raw.append((result.id, result.date, result.distance, result.time, kind, vdot, kind == .race ? 1 : 0.9))
        }
        for effort in FitnessEstimator.trainingEfforts(runs: runs, maxHeartRate: maxHeartRate, today: today, calendar: calendar)
        where !markedWorkouts.contains(effort.run.id) {
            raw.append((effort.run.id, effort.run.start, effort.run.distanceMeters ?? 0, effort.run.duration, .trainingEffort, effort.vdot, 0.5))
        }
        guard !raw.isEmpty else { return nil }
        let weighted = raw.map { item in (item, item.base * pow(0.5, ageDays(item.date) / halfLifeDays)) }

        // 2. Tendencia robusta (Theil–Sen) en VDOT por semana.
        let points = weighted.map { (weeks: -ageDays($0.0.date) / 7, vdot: $0.0.vdot) }
        let span = (points.map(\.weeks).max() ?? 0) - (points.map(\.weeks).min() ?? 0)
        var trend: Double?
        if points.count >= 3, span >= 3 {
            trend = theilSen(points.map { ($0.weeks, $0.vdot) }).map { min(max($0, -maximumWeeklyTrend), maximumWeeklyTrend) }
        }
        let slope = trend ?? 0

        // 3. Cada prueba llevada a hoy; coherencia frente a la mediana.
        let projected = weighted.map { ($0.0, $0.1, $0.0.vdot + slope * ageDays($0.0.date) / 7) }
        let center = weightedMedian(projected.map { ($0.2, $0.1) }) ?? projected[0].2
        let evidence = projected.map { item, weight, value -> (PerformanceEvidence, Double) in
            let inconsistent = projected.count >= 3 && abs(value - center) > inconsistencyLimit
            let finalWeight = inconsistent ? weight * 0.25 : weight
            return (PerformanceEvidence(id: item.id, date: item.date, distance: item.distance, time: item.time, kind: item.kind, vdot: item.vdot, weight: finalWeight, isInconsistent: inconsistent), value)
        }
        let totalWeight = evidence.map(\.0.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let current = evidence.map { $0.0.weight * $0.1 }.reduce(0, +) / totalWeight

        // 4. Incertidumbre.
        var spread = minimumUncertainty
        if evidence.count >= 2 {
            let variance = evidence.map { $0.0.weight * pow($0.1 - current, 2) }.reduce(0, +) / totalWeight
            spread = max(variance.squareRoot(), minimumUncertainty)
        }
        let newest = evidence.map(\.0).max { $0.date < $1.date }
        let hasRecentOfficial = evidence.contains { $0.0.kind != .trainingEffort && ageDays($0.0.date) <= Double(FitnessEstimator.freshDays) }
        if !hasRecentOfficial || (newest.map { ageDays($0.date) } ?? 999) > Double(FitnessEstimator.freshDays) {
            spread += 0.5
        }

        let confidence: PerformanceAssessment.Confidence
        if hasRecentOfficial && evidence.count >= 3 && spread <= 1.5 {
            confidence = .high
        } else if evidence.count >= 2 || hasRecentOfficial {
            confidence = .medium
        } else {
            confidence = .low
        }

        let official = evidence.map(\.0).filter { $0.kind != .trainingEffort && !$0.isInconsistent }
        return PerformanceAssessment(
            evidence: evidence.map(\.0).sorted { $0.date > $1.date },
            currentVDOT: current,
            uncertainty: spread,
            weeklyTrend: trend,
            confidence: confidence,
            riegelExponent: riegelExponent,
            personalExponent: personalExponent(official),
            hasInterval: evidence.count >= 3
        )
    }

    // MARK: Riegel

    public static func riegel(time: TimeInterval, from distance: Double, to target: Double, exponent: Double = defaultRiegelExponent) -> TimeInterval {
        time * pow(target / distance, exponent)
    }

    /// Cada prueba proyectada a la distancia, ponderada además por cercanía
    /// de distancia (las más parecidas pesan más). Media en escala logarítmica.
    static func riegelTime(evidence: [PerformanceEvidence], to target: Double, exponent: Double) -> TimeInterval? {
        var sum = 0.0, weights = 0.0
        for item in evidence where item.distance > 0 && item.time > 0 {
            let closeness = exp(-abs(log(target / item.distance)))
            let weight = item.weight * closeness
            sum += weight * log(riegel(time: item.time, from: item.distance, to: target, exponent: exponent))
            weights += weight
        }
        guard weights > 0 else { return nil }
        return exp(sum / weights)
    }

    /// Exponente personal: mediana de los pares de pruebas oficiales con
    /// distancias que difieren ×1,5 o más, si queda en un rango plausible.
    static func personalExponent(_ official: [PerformanceEvidence]) -> Double? {
        var values: [Double] = []
        for (i, a) in official.enumerated() {
            for b in official[(i + 1)...] where max(a.distance, b.distance) / min(a.distance, b.distance) >= 1.5 {
                let k = log(b.time / a.time) / log(b.distance / a.distance)
                if k.isFinite { values.append(k) }
            }
        }
        guard let median = median(values), plausibleExponent.contains(median) else { return nil }
        return median
    }

    // MARK: Estadística robusta

    /// Pendiente de Theil–Sen: mediana de las pendientes entre todos los pares.
    public static func theilSen(_ points: [(x: Double, y: Double)]) -> Double? {
        var slopes: [Double] = []
        for (i, a) in points.enumerated() {
            for b in points[(i + 1)...] where abs(b.x - a.x) > 1e-9 {
                slopes.append((b.y - a.y) / (b.x - a.x))
            }
        }
        return median(slopes)
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func weightedMedian(_ values: [(value: Double, weight: Double)]) -> Double? {
        let sorted = values.filter { $0.weight > 0 }.sorted { $0.value < $1.value }
        let total = sorted.map(\.weight).reduce(0, +)
        guard total > 0 else { return nil }
        var accumulated = 0.0
        for item in sorted {
            accumulated += item.weight
            if accumulated >= total / 2 { return item.value }
        }
        return sorted.last?.value
    }
}
