import Foundation

/// Evaluación retrospectiva del modelo de rendimiento con tus propios resultados.
///
/// Para cada test o competición registrada se arma el modelo **solo con lo
/// que había antes de ese día** (resultados y carreras anteriores; nada
/// posterior) y se compara su predicción para esa distancia con el tiempo
/// real. Así se mide cuánto acierta el modelo contigo:
/// - **MAE**: error absoluto medio (s y %).
/// - **RMSE**: raíz del error cuadrático medio (penaliza más los errores grandes).
/// - **Sesgo**: error medio con signo (positivo = el modelo predice más lento
///   de lo que corres: pesimista; negativo = optimista).
/// - **Cobertura**: qué fracción de tiempos reales cayó dentro del rango del
///   80 % que daba el modelo (bien calibrado ≈ 80 %).
/// - **Error relativo calibrado**: dispersión robusta (MAD × 1,4826) de los
///   errores relativos; con 5 casos o más se usa para que los rangos de las
///   predicciones nunca sean más estrechos que tu error real.
public struct PredictionBacktest: Hashable, Sendable {
    public struct Case: Hashable, Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let distance: Double
        public let actual: TimeInterval
        public let predicted: TimeInterval
        public let range: ClosedRange<TimeInterval>?
        /// Días entre la última prueba disponible y la predicha (horizonte real de información).
        public var horizonDays: Int = 0

        /// Segundos (positivo = el modelo esperaba más lento).
        public var error: TimeInterval { predicted - actual }
        public var relativeError: Double { actual > 0 ? error / actual : 0 }
        public var insideRange: Bool? { range.map { $0.contains(actual) } }
    }

    public let cases: [Case]

    public static let minimumCasesForCalibration = 5

    /// Error absoluto medio por horizonte (≤ 2 semanas, 2–6, más de 6).
    public struct HorizonError: Hashable, Sendable {
        public let label: String
        public let count: Int
        public let meanAbsoluteError: TimeInterval?
    }

    public var errorByHorizon: [HorizonError] {
        let buckets: [(String, ClosedRange<Int>)] = [("≤ 14 d", 0...14), ("15–42 d", 15...42), ("> 42 d", 43...100_000)]
        return buckets.map { label, range in
            let items = cases.filter { range.contains($0.horizonDays) }
            let mae = items.isEmpty ? nil : items.map { abs($0.error) }.reduce(0, +) / Double(items.count)
            return HorizonError(label: label, count: items.count, meanAbsoluteError: mae)
        }
    }

    /// Hay casos suficientes para hablar de precisión (si no: «Datos insuficientes para validar»).
    public var hasEnoughData: Bool { count >= Self.minimumCasesForCalibration }

    public var count: Int { cases.count }

    public var meanAbsoluteError: TimeInterval? {
        cases.isEmpty ? nil : cases.map { abs($0.error) }.reduce(0, +) / Double(cases.count)
    }

    public var meanAbsolutePercentageError: Double? {
        cases.isEmpty ? nil : cases.map { abs($0.relativeError) }.reduce(0, +) / Double(cases.count)
    }

    public var rootMeanSquareError: TimeInterval? {
        cases.isEmpty ? nil : (cases.map { $0.error * $0.error }.reduce(0, +) / Double(cases.count)).squareRoot()
    }

    public var bias: TimeInterval? {
        cases.isEmpty ? nil : cases.map(\.error).reduce(0, +) / Double(cases.count)
    }

    public var relativeBias: Double? {
        cases.isEmpty ? nil : cases.map(\.relativeError).reduce(0, +) / Double(cases.count)
    }

    /// Fracción de casos dentro del rango (solo los que tenían rango).
    public var coverage: Double? {
        let withRange = cases.compactMap(\.insideRange)
        guard !withRange.isEmpty else { return nil }
        return Double(withRange.filter { $0 }.count) / Double(withRange.count)
    }

    /// Desviación robusta del error relativo; `nil` con menos de 5 casos.
    public var calibratedRelativeError: Double? {
        guard cases.count >= Self.minimumCasesForCalibration else { return nil }
        let values = cases.map(\.relativeError).sorted()
        guard let median = RacePerformanceModel.median(values),
              let mad = RacePerformanceModel.median(values.map { abs($0 - median) }) else { return nil }
        return max(1.4826 * mad, 0.005)
    }

    /// Con los mismos parámetros que el modelo en vivo (correcciones de
    /// duplicados, descartes, plan y FC de umbral), para medir el mismo modelo.
    public static func run(results allResults: [PerformanceResult], runs: [WorkoutSummary], maxHeartRate: Double?, riegelExponent: Double = RacePerformanceModel.defaultRiegelExponent, distinct: Set<UUID> = [], rejected: Set<UUID> = [], plannedKinds: [Date: SessionKind] = [:], thresholdHeartRate: Double? = nil, calendar: Calendar) -> PredictionBacktest {
        // Un resultado duplicado no se evalúa dos veces.
        let results = RacePerformanceModel.deduplicated(allResults, distinct: distinct, calendar: calendar).kept
        let cases = results.sorted { $0.date < $1.date }.compactMap { target -> Case? in
            let dayStart = calendar.startOfDay(for: target.date)
            // Solo lo anterior al día de la prueba (sin fuga de información).
            let pastResults = results.filter { $0.date < dayStart && $0.id != target.id }
            let pastRuns = runs.filter { $0.start < dayStart && $0.id != target.workoutID }
            guard let model = RacePerformanceModel.assess(results: pastResults, runs: pastRuns, maxHeartRate: maxHeartRate, riegelExponent: riegelExponent, distinct: distinct, thresholdHeartRate: thresholdHeartRate, plannedKinds: plannedKinds, rejected: rejected, today: dayStart.addingTimeInterval(-1), calendar: calendar) else { return nil }
            let prediction = model.predict(target.distance)
            var item = Case(id: target.id, date: target.date, distance: target.distance, actual: target.time, predicted: prediction.time, range: prediction.range)
            if let last = pastResults.map(\.date).max() {
                item.horizonDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: dayStart).day ?? 0
            }
            return item
        }
        return PredictionBacktest(cases: cases)
    }
}

extension PredictionBacktest {
    /// Validación de la **proyección** (no del rendimiento de hoy): para cada
    /// test o competición, se arma el modelo con los datos de `horizonDays`
    /// días antes, se proyecta hasta ese día con el escenario central (con tu
    /// frecuencia real de las 4 semanas previas) y se compara con el tiempo real.
    public static func runProjection(results allResults: [PerformanceResult], runs: [WorkoutSummary], maxHeartRate: Double?, riegelExponent: Double = RacePerformanceModel.defaultRiegelExponent, distinct: Set<UUID> = [], rejected: Set<UUID> = [], plannedKinds: [Date: SessionKind] = [:], thresholdHeartRate: Double? = nil, horizonDays: Int = 28, calendar: Calendar) -> PredictionBacktest {
        let results = RacePerformanceModel.deduplicated(allResults, distinct: distinct, calendar: calendar).kept
        let cases = results.sorted { $0.date < $1.date }.compactMap { target -> Case? in
            let dayStart = calendar.startOfDay(for: target.date)
            guard let origin = calendar.date(byAdding: .day, value: -horizonDays, to: dayStart) else { return nil }
            let pastResults = results.filter { $0.date < origin }
            let pastRuns = runs.filter { $0.start < origin }
            guard let model = RacePerformanceModel.assess(results: pastResults, runs: pastRuns, maxHeartRate: maxHeartRate, riegelExponent: riegelExponent, distinct: distinct, thresholdHeartRate: thresholdHeartRate, plannedKinds: plannedKinds, rejected: rejected, today: origin.addingTimeInterval(-1), calendar: calendar) else { return nil }
            let monthBefore = calendar.date(byAdding: .day, value: -28, to: origin) ?? origin
            let frequency = Int((Double(pastRuns.filter { $0.activity.isRun && $0.start >= monthBefore }.count) / 4).rounded())
            let projection = GoalProjection.project(performance: model, weeks: horizonDays / 7, compliance: nil, runsPerWeek: max(frequency, 1), scenario: .central, today: origin.addingTimeInterval(-1), calendar: calendar)
            let predicted = VDOT.raceTime(vdot: projection.projectedVDOT, distance: target.distance)
            let range = VDOT.raceTime(vdot: projection.projectedVDOT + 1.28 * projection.uncertainty, distance: target.distance)...VDOT.raceTime(vdot: max(projection.projectedVDOT - 1.28 * projection.uncertainty, 15), distance: target.distance)
            var item = Case(id: target.id, date: target.date, distance: target.distance, actual: target.time, predicted: predicted, range: range)
            if let last = pastResults.map(\.date).max() {
                item.horizonDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: dayStart).day ?? 0
            }
            return item
        }
        return PredictionBacktest(cases: cases)
    }

    /// El rango solo puede llamarse "calibrado" con 5 casos o más y una
    /// cobertura observada razonable (entre 65 y 95 %).
    public var rangeIsCalibrated: Bool {
        guard count >= Self.minimumCasesForCalibration, let coverage else { return false }
        return (0.65...0.95).contains(coverage)
    }
}

/// Resultado real de un objetivo de plan (para calibrar la factibilidad).
public struct GoalOutcome: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let raceDate: Date
    public let goalTime: TimeInterval
    public let actualTime: TimeInterval
    /// Valor del modelo (0…1) unas semanas antes de la carrera.
    public let modelValue: Double

    public init(id: UUID = UUID(), raceDate: Date, goalTime: TimeInterval, actualTime: TimeInterval, modelValue: Double) {
        self.id = id
        self.raceDate = raceDate
        self.goalTime = goalTime
        self.actualTime = actualTime
        self.modelValue = modelValue
    }

    public var achieved: Bool { actualTime <= goalTime }
}

/// Calibración de la factibilidad con objetivos ya corridos.
///
/// - **Brier**: media de (probabilidad − resultado)², 0 = perfecto; 0,25 es
///   lo que da decir siempre 50 %. Solo con 5 objetivos o más, y solo si es
///   menor que 0,25, se permite mostrar el porcentaje del modelo.
public enum GoalCalibration {
    public static let minimumOutcomes = 5

    public static func brierScore(_ outcomes: [GoalOutcome]) -> Double? {
        guard !outcomes.isEmpty else { return nil }
        return outcomes.map { pow($0.modelValue - ($0.achieved ? 1 : 0), 2) }.reduce(0, +) / Double(outcomes.count)
    }

    public static func allowsPercentage(_ outcomes: [GoalOutcome]) -> Bool {
        guard outcomes.count >= minimumOutcomes, let brier = brierScore(outcomes) else { return false }
        return brier < 0.25
    }
}

extension PerformanceAssessment {
    /// Predicción con el rango ampliado, si hace falta, a tu error real medido
    /// (±1,28 × error relativo calibrado).
    public func predict(_ distance: Double, calibratedRelativeError: Double?) -> DistancePrediction {
        let base = predict(distance)
        guard let error = calibratedRelativeError, error > 0 else { return base }
        let half = 1.28 * error * base.time
        let lower = min(base.range?.lowerBound ?? base.time, base.time - half)
        let upper = max(base.range?.upperBound ?? base.time, base.time + half)
        return DistancePrediction(distance: base.distance, time: base.time, vdotTime: base.vdotTime, riegelTime: base.riegelTime, range: lower...upper)
    }
}
