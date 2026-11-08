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
    /// De dónde sale el peso (`nil` si no cuenta).
    public var factors: WeightFactors?
    /// VDOT que entra en la media (el de la prueba llevado a hoy con la
    /// tendencia, si la hay); `nil` si no cuenta.
    public var valueUsed: Double?

    /// Desglose del peso: peso = tipo × antigüedad × distancia × calidad × tope.
    public struct WeightFactors: Hashable, Sendable {
        /// Competición 1, test 0,9, entrenamiento 0,5.
        public let kind: Double
        /// Se reduce a la mitad cada 42 días.
        public let age: Double
        /// Menos de 1,5 km 0,6; de 1,5 a 3 km 0,85; 3 km o más 1.
        public let distance: Double
        /// En cinta 0,8 (la distancia es estimada); FC media < 85 % de la máxima 0,7 (quizá no fue a tope).
        public let quality: Double
        /// Reparto para que los entrenamientos no pesen más que la mitad de los tests (1 si no aplica).
        public let cap: Double
        public let qualityNotes: [QualityNote]
        /// 0,25 si no encaja con el resto de pruebas; 1 si encaja.
        public var consistency: Double = 1

        public var product: Double { kind * age * distance * quality * cap * consistency }
    }

    public enum QualityNote: String, Hashable, Sendable {
        case treadmill
        case lowHeartRate
    }

    public enum Role: Hashable, Sendable {
        /// Cuenta en la estimación con su peso.
        case counted
        /// Esfuerzo candidato **no confirmado** por debajo de tu forma: no la baja
        /// (un entrenamiento más lento no prueba que perdiste forma). Si fue a
        /// tope, confírmalo como test y contará, aunque sea más lento.
        case belowEstimate
        /// Candidato más de 3 puntos por debajo de tus tests: si hubiera sido a
        /// tope implicaría perder un 10 % de forma en días; es mucho más probable
        /// que no fuera un esfuerzo máximo. No cuenta (puedes confirmarlo).
        case notMaximal
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

    public init(id: UUID, date: Date, distance: Double, time: TimeInterval, kind: Kind, vdot: Double, weight: Double, isInconsistent: Bool, role: Role, factors: WeightFactors?) {
        self.init(id: id, date: date, distance: distance, time: time, kind: kind, vdot: vdot, weight: weight, isInconsistent: isInconsistent, role: role)
        self.factors = factors
    }
}

/// Predicción de una distancia por los dos métodos y su combinación.
public struct DistancePrediction: Hashable, Identifiable, Sendable {
    public let distance: Double
    /// Tiempo previsto hoy: el de Daniels con tu VDOT actual. Es la única
    /// definición de «hoy» en toda la app (objetivo, predicción, exportación) y
    /// la misma escala en que se proyecta la mejora. Hasta 1.4 era la media
    /// geométrica con Riegel, y no coincidía con el «hoy» del objetivo.
    public let time: TimeInterval
    /// Daniels: VDOT actual (con tendencia) → tiempo.
    public let vdotTime: TimeInterval
    /// Riegel: cada prueba proyectada a esta distancia, ponderada. Se usa como
    /// comprobación: si difiere de Daniels, el rango se ensancha.
    public let riegelTime: TimeInterval
    /// Rango orientativo (±1,28 σ, pensado como 80 %; sin validar hasta tener resultados).
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

    /// Pruebas que entran en la media (con peso > 0).
    public var countedEvidence: [PerformanceEvidence] {
        evidence.filter { ($0.role == .counted || $0.role == .inconsistent) && $0.weight > 0 }
    }

    /// El VDOT sale de una sola prueba o de una media ponderada de varias.
    public var isWeightedCombination: Bool { countedEvidence.count > 1 }

    /// Con menos de 3 resultados oficiales la tendencia es provisional.
    public var trendIsProvisional: Bool { officialCount < 3 || weeklyTrend == nil }

    public func predict(_ distance: Double) -> DistancePrediction {
        let vdotTime = VDOT.raceTime(vdot: currentVDOT, distance: distance)
        let riegelTime = RacePerformanceModel.riegelTime(evidence: evidence, to: distance, exponent: personalExponent ?? riegelExponent) ?? vdotTime
        var range: ClosedRange<TimeInterval>?
        if hasInterval {
            // Orientativo: ±1,28 σ en VDOT, ensanchado hasta incluir el tiempo de Riegel.
            let fast = VDOT.raceTime(vdot: currentVDOT + 1.28 * uncertainty, distance: distance)
            let slow = VDOT.raceTime(vdot: max(currentVDOT - 1.28 * uncertainty, 15), distance: distance)
            range = min(fast, riegelTime)...max(slow, riegelTime)
        }
        return DistancePrediction(distance: distance, time: vdotTime, vdotTime: vdotTime, riegelTime: riegelTime, range: range)
    }
}

/// Modelo de rendimiento: une VDOT (Daniels) y Riegel con varias pruebas.
///
/// Reglas (RUNNING_ENGINE.md, "Modelo de rendimiento"):
/// - **Pruebas**: tests y competiciones registrados (últimos 180 días) y
///   esfuerzos de entrenamiento comparables a una prueba (`FitnessEstimator.
///   trainingEfforts`, últimos 42 días, ya filtrados por calidad).
/// - **Peso**: tipo (competición 1, test 0,9, entrenamiento 0,5) ×
///   antigüedad (se reduce a la mitad cada 42 días) × distancia (< 1,5 km
///   0,6; 1,5–3 km 0,85) × calidad (cinta 0,8; FC media < 85 % de la máxima
///   0,7). Los entrenamientos suman como mucho la mitad del peso de los tests.
/// - **Duplicados**: mismo entrenamiento de Salud (id), o mismo día con tiempo
///   a ≤ 2 % y distancia a ≤ 3 %; se puede marcar «no es duplicado».
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
    /// Versión del algoritmo (se exporta junto a los resultados).
    public static let version = "1.5"
    public static let resultWindowDays = 180
    public static let halfLifeDays = 42.0
    public static let maximumWeeklyTrend = 0.25
    public static let inconsistencyLimit = 3.0
    public static let minimumUncertainty = 0.8
    public static let defaultRiegelExponent = 1.06
    public static let plausibleExponent: ClosedRange<Double> = 1.01...1.15

    /// Fiabilidad por distancia: las pruebas muy cortas dependen mucho de la
    /// capacidad anaeróbica y de errores de cronometraje; el VDOT de Daniels
    /// está pensado para pruebas de ≈ 1,5 km en adelante.
    public static func distanceFactor(_ meters: Double) -> Double {
        meters < 1500 ? 0.6 : (meters < 3000 ? 0.85 : 1)
    }

    /// Los entrenamientos no pueden sumar más de la mitad del peso de los tests.
    public static let trainingShareCap = 0.5
    /// FC media por debajo de esta fracción de la máxima: el test quizá no fue a tope.
    public static let lowTestHeartRate = 0.85

    /// Tolerancias para considerar dos resultados como el mismo esfuerzo.
    public static let duplicateTimeTolerance = 0.02
    /// Además del mismo día: a ±12 h (un test a las 23:50 cargado a mano «al día siguiente»).
    public static let duplicateWindow: TimeInterval = 12 * 3600
    public static let duplicateDistanceTolerance = 0.03

    /// Resultados sin duplicados: mismo día, tiempo a ≤ 2 % y distancia a ≤ 3 %
    /// (p. ej. uno cargado a mano "3,00 km" y otro del entrenamiento "3,026 km").
    /// Se queda el que viene de un entrenamiento de Salud (distancia exacta); si
    /// ninguno, el más reciente en la lista. Devuelve también los descartados.
    /// `distinct`: ids que marcaste como «no es un duplicado» (no se fusionan).
    public static func deduplicated(_ results: [PerformanceResult], distinct: Set<UUID> = [], calendar: Calendar) -> (kept: [PerformanceResult], duplicates: [(PerformanceResult, keptID: UUID)]) {
        var kept: [PerformanceResult] = []
        var duplicates: [(PerformanceResult, keptID: UUID)] = []
        // Primero los que tienen entrenamiento de origen.
        // Orden total (independiente del orden de entrada): primero los que
        // vienen de un entrenamiento, luego el más antiguo, luego por id.
        let ordered = results.sorted { a, b in
            let rankA = a.workoutID != nil ? 0 : 1, rankB = b.workoutID != nil ? 0 : 1
            if rankA != rankB { return rankA < rankB }
            if a.date != b.date { return a.date < b.date }
            return a.id.uuidString < b.id.uuidString
        }
        for result in ordered {
            if let match = kept.first(where: { other in
                // Mismo entrenamiento de Salud (identificador único): siempre duplicado.
                if let id = result.workoutID, id == other.workoutID { return true }
                if distinct.contains(result.id) || distinct.contains(other.id) { return false }
                let close = calendar.isDate(other.date, inSameDayAs: result.date) || abs(other.date.timeIntervalSince(result.date)) <= duplicateWindow
                return close
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

    public static func assess(results allResults: [PerformanceResult], runs: [WorkoutSummary], maxHeartRate: Double? = nil, riegelExponent: Double = defaultRiegelExponent, distinct: Set<UUID> = [], thresholdHeartRate: Double? = nil, plannedKinds: [Date: SessionKind] = [:], rejected: Set<UUID> = [], today: Date, calendar: Calendar) -> PerformanceAssessment? {
        let todayStart = calendar.startOfDay(for: today)
        func ageDays(_ date: Date) -> Double {
            Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: todayStart).day ?? 0)
        }
        func decay(_ date: Date) -> Double { pow(0.5, ageDays(date) / halfLifeDays) }

        // 1. Resultados oficiales (tests y competiciones), sin duplicados.
        let window = allResults.filter { $0.date <= today && ageDays($0.date) <= Double(resultWindowDays) && $0.vdot != nil }
        let (results, duplicates) = deduplicated(window, distinct: distinct, calendar: calendar)
        let markedWorkouts = Set(allResults.compactMap(\.workoutID))
        let quality = DataQuality.assess(runs)
        let referenceMax = EffortClassifier.referenceMaxHeartRate(configured: maxHeartRate, runs: runs.filter { quality[$0.id]?.heartRateUsable != false })
        let runsByID = Dictionary(runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var factorsByID: [UUID: PerformanceEvidence.WeightFactors] = [:]
        var official: [(result: PerformanceResult, kind: PerformanceEvidence.Kind, vdot: Double, weight: Double)] = results.compactMap { result in
            guard let vdot = result.vdot else { return nil }
            let kind: PerformanceEvidence.Kind = result.kind == .race ? .race : .test
            // Calidad: solo con el entrenamiento de Salud del que sale.
            var qualityFactor = 1.0
            var notes: [PerformanceEvidence.QualityNote] = []
            if let id = result.workoutID, let workout = runsByID[id] {
                if workout.activity == .indoorRun {
                    qualityFactor *= 0.8
                    notes.append(.treadmill)
                }
                if let average = workout.averageHeartRate, let referenceMax, quality[id]?.heartRateUsable != false,
                   average / referenceMax < lowTestHeartRate {
                    qualityFactor *= 0.7
                    notes.append(.lowHeartRate)
                }
            }
            let factors = PerformanceEvidence.WeightFactors(kind: kind == .race ? 1 : 0.9, age: decay(result.date), distance: distanceFactor(result.distance), quality: qualityFactor, cap: 1, qualityNotes: notes)
            factorsByID[result.id] = factors
            return (result, kind, vdot, factors.product)
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
        // Sin los ya marcados ni los equivalentes a un resultado registrado (p. ej.
        // la copia de un entrenamiento marcado que quedó tras deduplicar).
        let efforts = FitnessEstimator.trainingEfforts(runs: runs.filter { $0.activity == .outdoorRun }, maxHeartRate: maxHeartRate, referenceRuns: runs, thresholdHeartRate: thresholdHeartRate, plannedKinds: plannedKinds, rejected: rejected, today: today, calendar: calendar)
            .filter { !markedWorkouts.contains($0.run.id) }
            .filter { effort in
                let asResult = PerformanceResult(id: effort.run.id, date: effort.run.start, distance: effort.run.distanceMeters ?? 0, time: effort.run.duration, kind: .test)
                return !window.contains { deduplicated([$0, asResult], calendar: calendar).kept.count == 1 }
            }
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
            var factors = factorsByID[item.result.id]
            if inconsistent { factors?.consistency = 0.25 }
            return PerformanceEvidence(id: item.result.id, date: item.result.date, distance: item.result.distance, time: item.result.time, kind: item.kind, vdot: item.vdot, weight: item.weight, isInconsistent: inconsistent, role: inconsistent ? .inconsistent : .counted, factors: factors)
        }
        for (pair, duplicateOf) in duplicates {
            guard let vdot = pair.vdot else { continue }
            evidence.append(PerformanceEvidence(id: pair.id, date: pair.date, distance: pair.distance, time: pair.time, kind: pair.kind == .race ? .race : .test, vdot: vdot, weight: 0, isInconsistent: false, role: .duplicate(of: duplicateOf)))
        }
        for effort in efforts {
            let distance = effort.run.distanceMeters ?? 0
            let isOutlier = efforts.count >= 2 && effort.run.id == efforts.first?.run.id && effort.vdot - efforts[1].vdot > FitnessEstimator.outlierGap
            let trainingFactors = PerformanceEvidence.WeightFactors(kind: 0.5, age: decay(effort.run.start), distance: distanceFactor(distance), quality: 1, cap: 1, qualityNotes: [])
            if (effort.vdot > base + 0.05 && !isOutlier) || (officialEstimate == nil && abs(effort.vdot - base) < 0.05) {
                let weight = trainingFactors.product
                counted.append((effort.run.id, effort.vdot, weight))
                evidence.append(PerformanceEvidence(id: effort.run.id, date: effort.run.start, distance: distance, time: effort.run.duration, kind: .trainingEffort, vdot: effort.vdot, weight: weight, isInconsistent: false, role: .counted, factors: trainingFactors))
            } else {
                let role: PerformanceEvidence.Role = isOutlier ? .inconsistent : (effort.vdot < base - inconsistencyLimit ? .notMaximal : .belowEstimate)
                evidence.append(PerformanceEvidence(id: effort.run.id, date: effort.run.start, distance: distance, time: effort.run.duration, kind: .trainingEffort, vdot: effort.vdot, weight: 0, isInconsistent: isOutlier, role: role))
            }
        }
        // Tope: con tests o competiciones, los entrenamientos suman como mucho
        // la mitad de su peso (un único entrenamiento no decide tu forma).
        if officialWeight > 0 {
            let trainingIDs = Set(evidence.filter { $0.kind == .trainingEffort && $0.role == .counted }.map(\.id))
            let trainingWeight = counted.filter { trainingIDs.contains($0.id) }.map(\.weight).reduce(0, +)
            let limit = trainingShareCap * officialWeight
            if trainingWeight > limit, trainingWeight > 0 {
                let scale = limit / trainingWeight
                counted = counted.map { trainingIDs.contains($0.id) ? ($0.id, $0.value, $0.weight * scale) : $0 }
                evidence = evidence.map { item in
                    guard trainingIDs.contains(item.id), let f = item.factors else { return item }
                    var capped = PerformanceEvidence.WeightFactors(kind: f.kind, age: f.age, distance: f.distance, quality: f.quality, cap: scale, qualityNotes: f.qualityNotes)
                    capped.consistency = f.consistency
                    return PerformanceEvidence(id: item.id, date: item.date, distance: item.distance, time: item.time, kind: item.kind, vdot: item.vdot, weight: capped.product, isInconsistent: item.isInconsistent, role: item.role, factors: capped)
                }
            }
        }
        let totalWeight = counted.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let usedValues = Dictionary(counted.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        evidence = evidence.map { item in
            var item = item
            item.valueUsed = item.weight > 0 ? usedValues[item.id] : nil
            return item
        }
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
