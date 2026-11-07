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
    /// Cómo se usó y por qué.
    public let role: Role

    public enum Role: Hashable, Sendable {
        /// Cuenta en la estimación con su peso.
        case counted
        /// Entrenamiento por debajo de tu forma: no la baja (solo prueba un mínimo).
        case belowEstimate
        /// El mismo resultado registrado dos veces: cuenta una sola vez.
        case duplicate(of: UUID)
        /// No encaja con el resto: cuenta con un cuarto del peso.
        case inconsistent
    }

    public init(id: UUID, date: Date, distance: Double, time: TimeInterval, kind: Kind, vdot: Double, weight: Double, isInconsistent: Bool, role: Role = .counted) {
        self.id = id
        self.date = date
        self.distance = distance
        self.time = time
        self.kind = kind
        self.vdot = vdot
        self.weight = weight
        self.isInconsistent = isInconsistent
        self.role = role
    }
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
    /// Hay datos suficientes para dar un intervalo (orientativo hasta calibrarlo).
    public let hasInterval: Bool
    /// Tests y competiciones que cuentan (sin duplicados ni incoherentes).
    public var officialCount: Int = 0
    /// Tamaño efectivo de la muestra (Kish).
    public var effectiveSampleSize: Double = 1

    /// Con menos de 3 resultados oficiales la tendencia es provisional.
    public var trendIsProvisional: Bool { officialCount < 3 || weeklyTrend == nil }

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

    /// Tolerancias para considerar dos resultados como el mismo esfuerzo.
    public static let duplicateTimeTolerance = 0.02
    public static let duplicateDistanceTolerance = 0.03

    /// Resultados sin duplicados: mismo día, tiempo a ≤ 2 % y distancia a ≤ 3 %
    /// (p. ej. uno cargado a mano "3,00 km" y otro del entrenamiento "3,026 km").
    /// Se queda el que viene de un entrenamiento de Salud (distancia exacta); si
    /// ninguno, el más reciente en la lista. Devuelve también los descartados.
    public static func deduplicated(_ results: [PerformanceResult], calendar: Calendar) -> (kept: [PerformanceResult], duplicates: [(PerformanceResult, keptID: UUID)]) {
        var kept: [PerformanceResult] = []
        var duplicates: [(PerformanceResult, keptID: UUID)] = []
        // Primero los que tienen entrenamiento de origen.
        for result in results.sorted(by: { ($0.workoutID != nil ? 0 : 1) < ($1.workoutID != nil ? 0 : 1) }) {
            if let match = kept.first(where: { other in
                calendar.isDate(other.date, inSameDayAs: result.date)
                    && abs(other.time - result.time) / max(other.time, 1) <= duplicateTimeTolerance
                    && abs(other.distance - result.distance) / max(other.distance, 1) <= duplicateDistanceTolerance
            }) {
                duplicates.append((result, match.id))
            } else {
                kept.append(result)
            }
        }
        return (kept, duplicates)
    }

    public static func assess(results allResults: [PerformanceResult], runs: [WorkoutSummary], maxHeartRate: Double? = nil, riegelExponent: Double = defaultRiegelExponent, today: Date, calendar: Calendar) -> PerformanceAssessment? {
        let todayStart = calendar.startOfDay(for: today)
        func ageDays(_ date: Date) -> Double {
            Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: todayStart).day ?? 0)
        }
        func decay(_ date: Date) -> Double { pow(0.5, ageDays(date) / halfLifeDays) }

        // 1. Resultados oficiales (tests y competiciones), sin duplicados.
        let window = allResults.filter { $0.date <= today && ageDays($0.date) <= Double(resultWindowDays) && $0.vdot != nil }
        let (results, duplicates) = deduplicated(window, calendar: calendar)
        let markedWorkouts = Set(allResults.compactMap(\.workoutID))
        var official: [(result: PerformanceResult, kind: PerformanceEvidence.Kind, vdot: Double, weight: Double)] = results.compactMap { result in
            guard let vdot = result.vdot else { return nil }
            let kind: PerformanceEvidence.Kind = result.kind == .race ? .race : .test
            return (result, kind, vdot, (kind == .race ? 1 : 0.9) * decay(result.date))
        }

        // 2. Tendencia solo con resultados oficiales (los entrenamientos no son
        //    comparables entre sí): 3 o más en 21 días o más.
        var trend: Double?
        let officialPoints = official.map { (x: -ageDays($0.result.date) / 7, y: $0.vdot) }
        let span = (officialPoints.map(\.x).max() ?? 0) - (officialPoints.map(\.x).min() ?? 0)
        if officialPoints.count >= 3, span >= 3 {
            trend = theilSen(officialPoints).map { min(max($0, -maximumWeeklyTrend), maximumWeeklyTrend) }
        }
        let slope = trend ?? 0
        func projected(_ vdot: Double, _ date: Date) -> Double { vdot + slope * ageDays(date) / 7 }

        // 3. Coherencia entre oficiales (con 3 o más).
        var inconsistentIDs = Set<UUID>()
        if official.count >= 3, let center = weightedMedian(official.map { (projected($0.vdot, $0.result.date), $0.weight) }) {
            for item in official where abs(projected(item.vdot, item.result.date) - center) > inconsistencyLimit {
                inconsistentIDs.insert(item.result.id)
            }
            official = official.map { item in
                inconsistentIDs.contains(item.result.id) ? (item.result, item.kind, item.vdot, item.weight * 0.25) : item
            }
        }
        let officialWeight = official.map(\.weight).reduce(0, +)
        let officialEstimate: Double? = officialWeight > 0
            ? official.map { $0.weight * projected($0.vdot, $0.result.date) }.reduce(0, +) / officialWeight
            : nil

        // 4. Esfuerzos detectados en entrenamientos (solo al aire libre, sin
        //    los ya marcados). Solo pueden SUBIR la estimación: un entrenamiento
        //    más lento no demuestra que hayas perdido forma.
        let efforts = FitnessEstimator.trainingEfforts(runs: runs.filter { $0.activity == .outdoorRun }, maxHeartRate: maxHeartRate, today: today, calendar: calendar)
            .filter { !markedWorkouts.contains($0.run.id) }
        var floor = officialEstimate
        if floor == nil, let best = efforts.first {
            // Sin resultados oficiales: el mejor esfuerzo (o el segundo, si el
            // mejor está más de 5 puntos por encima: probable error de GPS).
            floor = efforts.count >= 2 && best.vdot - efforts[1].vdot > FitnessEstimator.outlierGap ? efforts[1].vdot : best.vdot
        }
        guard let base = floor else { return nil }

        var counted: [(id: UUID, value: Double, weight: Double)] = official.map { ($0.result.id, projected($0.vdot, $0.result.date), $0.weight) }
        var evidence: [PerformanceEvidence] = official.map { item in
            let inconsistent = inconsistentIDs.contains(item.result.id)
            return PerformanceEvidence(id: item.result.id, date: item.result.date, distance: item.result.distance, time: item.result.time, kind: item.kind, vdot: item.vdot, weight: item.weight, isInconsistent: inconsistent, role: inconsistent ? .inconsistent : .counted)
        }
        for (pair, duplicateOf) in duplicates {
            guard let vdot = pair.vdot else { continue }
            evidence.append(PerformanceEvidence(id: pair.id, date: pair.date, distance: pair.distance, time: pair.time, kind: pair.kind == .race ? .race : .test, vdot: vdot, weight: 0, isInconsistent: false, role: .duplicate(of: duplicateOf)))
        }
        for effort in efforts {
            let distance = effort.run.distanceMeters ?? 0
            let isOutlier = efforts.count >= 2 && effort.run.id == efforts.first?.run.id && effort.vdot - efforts[1].vdot > FitnessEstimator.outlierGap
            if effort.vdot > base + 0.05, !isOutlier {
                let weight = 0.5 * decay(effort.run.start)
                counted.append((effort.run.id, effort.vdot, weight))
                evidence.append(PerformanceEvidence(id: effort.run.id, date: effort.run.start, distance: distance, time: effort.run.duration, kind: .trainingEffort, vdot: effort.vdot, weight: weight, isInconsistent: false, role: .counted))
            } else if officialEstimate == nil, abs(effort.vdot - base) < 0.05 {
                counted.append((effort.run.id, effort.vdot, 0.5 * decay(effort.run.start)))
                evidence.append(PerformanceEvidence(id: effort.run.id, date: effort.run.start, distance: distance, time: effort.run.duration, kind: .trainingEffort, vdot: effort.vdot, weight: 0.5 * decay(effort.run.start), isInconsistent: false, role: .counted))
            } else {
                evidence.append(PerformanceEvidence(id: effort.run.id, date: effort.run.start, distance: distance, time: effort.run.duration, kind: .trainingEffort, vdot: effort.vdot, weight: 0, isInconsistent: isOutlier, role: isOutlier ? .inconsistent : .belowEstimate))
            }
        }
        let totalWeight = counted.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let current = counted.map { $0.weight * $0.value }.reduce(0, +) / totalWeight

        // 5. Incertidumbre: dispersión ponderada (mínimo 0,8) inflada por el
        //    tamaño efectivo de la muestra (Kish: (Σw)²/Σw²), para que pocas
        //    pruebas —o pruebas casi iguales— no den un rango falsamente estrecho.
        var deviation = minimumUncertainty
        if counted.count >= 2 {
            let variance = counted.map { $0.weight * pow($0.value - current, 2) }.reduce(0, +) / totalWeight
            deviation = max(variance.squareRoot(), minimumUncertainty)
        }
        let squares = counted.map { $0.weight * $0.weight }.reduce(0, +)
        let effectiveSize = squares > 0 ? totalWeight * totalWeight / squares : 1
        var spread = deviation * (1 + 1 / max(effectiveSize, 1)).squareRoot()
        let newest = counted.compactMap { item in evidence.first { $0.id == item.id }?.date }.max()
        let hasRecentOfficial = official.contains { ageDays($0.result.date) <= Double(FitnessEstimator.freshDays) }
        if !hasRecentOfficial || (newest.map(ageDays) ?? 999) > Double(FitnessEstimator.freshDays) {
            spread += 0.5
        }

        let countedOfficial = official.filter { !inconsistentIDs.contains($0.result.id) }.count
        let confidence: PerformanceAssessment.Confidence
        if hasRecentOfficial && countedOfficial >= 3 && spread <= 1.5 {
            confidence = .high
        } else if hasRecentOfficial || counted.count >= 2 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let officialEvidence = evidence.filter { $0.kind != .trainingEffort && $0.role == .counted }
        return PerformanceAssessment(
            evidence: evidence.sorted { $0.date > $1.date },
            currentVDOT: current,
            uncertainty: spread,
            weeklyTrend: trend,
            confidence: confidence,
            riegelExponent: riegelExponent,
            personalExponent: personalExponent(officialEvidence),
            hasInterval: counted.count >= 2,
            officialCount: countedOfficial,
            effectiveSampleSize: effectiveSize
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
