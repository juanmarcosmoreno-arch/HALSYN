import Foundation

/// Historial diario por métrica, indexado por inicio de día.
public struct DailyHistory: Sendable {
    private var values: [MetricKind: [Date: Double]] = [:]
    public let calendar: Calendar

    public init(series: [MetricSeries], calendar: Calendar) {
        self.calendar = calendar
        for item in series {
            var byDay: [Date: Double] = [:]
            for value in item.values {
                byDay[calendar.startOfDay(for: value.day)] = value.value
            }
            values[item.kind] = byDay
        }
    }

    public func value(_ kind: MetricKind, on day: Date) -> Double? {
        values[kind]?[calendar.startOfDay(for: day)]
    }

    /// Valores existentes en los `days` días anteriores a `day` (sin incluirlo).
    public func values(_ kind: MetricKind, daysBefore day: Date, count days: Int) -> [Double] {
        let start = calendar.startOfDay(for: day)
        return (1...max(days, 1)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: start).flatMap { value(kind, on: $0) }
        }
    }
}

/// Parámetros del motor. Los umbrales provienen de recomendaciones públicas
/// (ver SCIENTIFIC_REFERENCES.md) y sirven de referencia orientativa: la
/// puntuación en conjunto NO está validada clínicamente.
public struct HealthScoreConfiguration: Sendable {
    public var weights: HealthScoreWeights
    /// Fracción mínima del peso con datos para dar una puntuación global.
    public var minimumCoverage: Double
    /// Días previos usados como referencia personal.
    public var baselineDays: Int
    /// Días mínimos de referencia para comparar con la media personal.
    public var minimumBaselineDays: Int
    /// Sueño recomendado para adultos (horas).
    public var recommendedSleep: ClosedRange<Double>
    /// Media diaria de pasos a partir de la cual no se suma más.
    public var stepsReference: Double
    /// Minutos semanales de actividad moderada-vigorosa de referencia.
    public var weeklyExerciseReference: Double

    public init(
        weights: HealthScoreWeights = .provisional,
        minimumCoverage: Double = 0.6,
        baselineDays: Int = 28,
        minimumBaselineDays: Int = 7,
        recommendedSleep: ClosedRange<Double> = 7...9,
        stepsReference: Double = 8000,
        weeklyExerciseReference: Double = 150
    ) {
        self.weights = weights
        self.minimumCoverage = minimumCoverage
        self.baselineDays = baselineDays
        self.minimumBaselineDays = minimumBaselineDays
        self.recommendedSleep = recommendedSleep
        self.stepsReference = stepsReference
        self.weeklyExerciseReference = weeklyExerciseReference
    }
}

/// Motor de la puntuación diaria de bienestar (0–100) de HÄLSA.
///
/// Reglas (documentadas en Documentation/HEALTH_SCORE.md):
/// - **Sueño**: horas de la noche que termina ese día frente a la recomendación
///   de 7–9 h. Dormir más de 9 h baja la puntuación muy poco.
/// - **Cardiovascular**: FC en reposo y HRV de ese día frente a la media personal
///   de los 28 días anteriores (mínimo 7). Estar por debajo de la FC en reposo
///   habitual o por encima de la HRV habitual NO suma más: solo se penalizan
///   desviaciones desfavorables claras. FC en reposo y HRV se promedian entre sí
///   para no contar dos veces la misma señal.
/// - **Movimiento**: media de pasos de los 7 días completos anteriores; a partir
///   de 8.000 al día no suma más.
/// - **Ejercicio**: minutos de ejercicio de los 7 días completos anteriores frente
///   a 150 min/semana. Al ser semanal, un día de descanso no penaliza.
/// - **Equilibrio**: carga aguda (7 días) frente a crónica (28 días) con minutos
///   de ejercicio. Una carga más baja de lo habitual apenas resta.
/// - Se usan días completos para movimiento y ejercicio, de modo que la
///   puntuación de hoy no baja por ir a media jornada.
/// - Sin cobertura suficiente (60 % del peso) no hay puntuación global.
public struct HealthScoreEngine: Sendable {
    public static let version = "0.1-provisional"

    public let configuration: HealthScoreConfiguration

    public init(configuration: HealthScoreConfiguration = HealthScoreConfiguration()) {
        self.configuration = configuration
    }

    /// Tipos que necesita el motor.
    public static let inputs: [MetricKind] = [.sleepDuration, .restingHeartRate, .heartRateVariability, .steps, .exerciseTime]

    /// Días de historial necesarios antes del primer día evaluado.
    public var historyDaysNeeded: Int { configuration.baselineDays + 1 }

    public struct Result: Hashable, Sendable {
        public let score: Int?
        public let breakdown: HealthScoreBreakdown
    }

    public func evaluate(day: Date, history: DailyHistory) -> Result {
        var dimensions: [DimensionScore] = []
        var factors: [ScoreFactor] = []
        var baselineDepth = 0

        for dimension in HealthScoreDimension.allCases {
            let weight = configuration.weights.weight(for: dimension)
            let outcome: (score: Double?, missing: DimensionScore.MissingReason?, factors: [ScoreFactor])
            switch dimension {
            case .sleep: outcome = sleep(day: day, history: history)
            case .cardiovascular:
                let result = cardiovascular(day: day, history: history)
                baselineDepth = result.baselineDays
                outcome = (result.score, result.missing, result.factors)
            case .movement: outcome = movement(day: day, history: history)
            case .exercise: outcome = exercise(day: day, history: history)
            case .balance: outcome = balance(day: day, history: history)
            }
            dimensions.append(DimensionScore(dimension: dimension, score: outcome.score.map { Int($0.rounded()) }, weight: weight, missingReason: outcome.missing))
            factors += outcome.factors
        }

        let totalWeight = configuration.weights.total
        let available = dimensions.filter { $0.score != nil && $0.weight > 0 }
        let availableWeight = available.reduce(0) { $0 + $1.weight }
        let coverage = totalWeight > 0 ? availableWeight / totalWeight : 0

        var score: Int?
        if configuration.weights.isValid, coverage >= configuration.minimumCoverage, availableWeight > 0 {
            let weighted = available.reduce(0.0) { $0 + Double($1.score ?? 0) * $1.weight }
            score = Int((weighted / availableWeight).rounded())
        }

        let confidence: ScoreConfidence
        if coverage >= 0.9 && baselineDepth >= 14 {
            confidence = .high
        } else if coverage >= 0.75 {
            confidence = .medium
        } else {
            confidence = .low
        }

        // Primero lo desfavorable, luego por peso de la dimensión.
        let impactOrder: [ScoreImpact: Int] = [.negative: 0, .positive: 1, .neutral: 2]
        let sortedFactors = factors.sorted {
            let lhs = (impactOrder[$0.impact] ?? 3, -configuration.weights.weight(for: $0.dimension))
            let rhs = (impactOrder[$1.impact] ?? 3, -configuration.weights.weight(for: $1.dimension))
            return lhs < rhs
        }

        return Result(
            score: score,
            breakdown: HealthScoreBreakdown(dimensions: dimensions, coverage: coverage, confidence: confidence, factors: sortedFactors, engineVersion: Self.version)
        )
    }

    // MARK: Dimensiones

    func sleep(day: Date, history: DailyHistory) -> (Double?, DimensionScore.MissingReason?, [ScoreFactor]) {
        guard let hours = history.value(.sleepDuration, on: day) else { return (nil, .noData, []) }
        let range = configuration.recommendedSleep
        let impact: ScoreImpact = range.contains(hours) ? .positive : (hours < range.lowerBound - 1 ? .negative : .neutral)
        return (Self.sleepScore(hours: hours, recommended: range), nil, [ScoreFactor(kind: .sleepDuration(hours: hours), dimension: .sleep, impact: impact)])
    }

    func cardiovascular(day: Date, history: DailyHistory) -> (score: Double?, missing: DimensionScore.MissingReason?, factors: [ScoreFactor], baselineDays: Int) {
        var scores: [Double] = []
        var factors: [ScoreFactor] = []
        var sawData = false
        var depth = 0

        if let today = history.value(.restingHeartRate, on: day) {
            sawData = true
            let baseline = history.values(.restingHeartRate, daysBefore: day, count: configuration.baselineDays)
            depth = max(depth, baseline.count)
            if baseline.count >= configuration.minimumBaselineDays {
                let stats = Statistics(baseline)
                let delta = today - stats.mean
                let z = delta / max(stats.standardDeviation, 2)
                scores.append(Self.unfavourableDeviationScore(z: z))
                factors.append(ScoreFactor(kind: .restingHeartRate(deltaFromBaseline: delta), dimension: .cardiovascular, impact: z > 1 ? .negative : .positive))
            }
        }
        if let today = history.value(.heartRateVariability, on: day) {
            sawData = true
            let baseline = history.values(.heartRateVariability, daysBefore: day, count: configuration.baselineDays)
            depth = max(depth, baseline.count)
            if baseline.count >= configuration.minimumBaselineDays {
                let stats = Statistics(baseline)
                let z = (today - stats.mean) / max(stats.standardDeviation, stats.mean * 0.05, 1)
                // Para la HRV, lo desfavorable es estar por debajo: se invierte el signo.
                scores.append(Self.unfavourableDeviationScore(z: -z))
                let relative = stats.mean > 0 ? (today - stats.mean) / stats.mean : 0
                factors.append(ScoreFactor(kind: .heartRateVariability(relativeDeltaFromBaseline: relative), dimension: .cardiovascular, impact: z < -1 ? .negative : .positive))
            }
        }
        guard !scores.isEmpty else {
            return (nil, sawData ? .insufficientHistory : .noData, [], depth)
        }
        return (scores.reduce(0, +) / Double(scores.count), nil, factors, depth)
    }

    func movement(day: Date, history: DailyHistory) -> (Double?, DimensionScore.MissingReason?, [ScoreFactor]) {
        let recent = history.values(.steps, daysBefore: day, count: 7)
        guard recent.count >= 4 else { return (nil, recent.isEmpty ? .noData : .insufficientHistory, []) }
        let average = recent.reduce(0, +) / Double(recent.count)
        let reference = configuration.stepsReference
        let impact: ScoreImpact = average >= reference ? .positive : (average >= reference * 0.625 ? .neutral : .negative)
        return (min(100, average / reference * 100), nil, [ScoreFactor(kind: .averageSteps(perDay: average), dimension: .movement, impact: impact)])
    }

    func exercise(day: Date, history: DailyHistory) -> (Double?, DimensionScore.MissingReason?, [ScoreFactor]) {
        let recent = history.values(.exerciseTime, daysBefore: day, count: 7)
        guard recent.count >= 4 else { return (nil, recent.isEmpty ? .noData : .insufficientHistory, []) }
        // Los días sin registro dentro de la semana cuentan como 0 min: es una suma semanal.
        let minutes = recent.reduce(0, +)
        let reference = configuration.weeklyExerciseReference
        let impact: ScoreImpact = minutes >= reference ? .positive : (minutes >= reference / 2 ? .neutral : .negative)
        return (min(100, minutes / reference * 100), nil, [ScoreFactor(kind: .weeklyExercise(minutes: minutes), dimension: .exercise, impact: impact)])
    }

    func balance(day: Date, history: DailyHistory) -> (Double?, DimensionScore.MissingReason?, [ScoreFactor]) {
        let acuteValues = history.values(.exerciseTime, daysBefore: day, count: 7)
        let chronicValues = history.values(.exerciseTime, daysBefore: day, count: configuration.baselineDays)
        guard !chronicValues.isEmpty else { return (nil, .noData, []) }
        guard acuteValues.count >= 4, chronicValues.count >= 14 else { return (nil, .insufficientHistory, []) }
        let acute = acuteValues.reduce(0, +) / 7
        let chronic = chronicValues.reduce(0, +) / Double(configuration.baselineDays)
        // Con una carga habitual casi nula el cociente no tiene sentido.
        guard chronic >= 5 else { return (nil, .insufficientHistory, []) }
        let ratio = acute / chronic
        let impact: ScoreImpact = ratio > 1.3 ? .negative : (ratio < 0.8 ? .neutral : .positive)
        return (Self.loadBalanceScore(ratio: ratio), nil, [ScoreFactor(kind: .trainingLoadRatio(ratio), dimension: .balance, impact: impact)])
    }

    // MARK: Curvas (públicas para tests y documentación)

    /// 100 dentro del rango recomendado; baja linealmente hasta 0 a 3 h por debajo
    /// del mínimo; por encima del máximo baja suavemente hasta un suelo de 70.
    public static func sleepScore(hours: Double, recommended: ClosedRange<Double>) -> Double {
        if recommended.contains(hours) { return 100 }
        if hours < recommended.lowerBound {
            return max(0, 100 - (recommended.lowerBound - hours) / 3 * 100)
        }
        return max(70, 100 - (hours - recommended.upperBound) / 2 * 30)
    }

    /// `z` = desviación desfavorable en desviaciones típicas. Hasta 1 no resta;
    /// de 1 a 3 baja linealmente de 100 a 40; a partir de ahí, 40.
    public static func unfavourableDeviationScore(z: Double) -> Double {
        if z <= 1 { return 100 }
        if z >= 3 { return 40 }
        return 100 - (z - 1) / 2 * 60
    }

    /// 100 entre 0,8 y 1,3. Por encima baja hasta 40 en 2,0; por debajo, solo
    /// hasta 70 en 0,3 (una carga menor de lo habitual no es un problema en sí).
    public static func loadBalanceScore(ratio: Double) -> Double {
        if (0.8...1.3).contains(ratio) { return 100 }
        if ratio > 1.3 { return max(40, 100 - (ratio - 1.3) / 0.7 * 60) }
        return max(70, 100 - (0.8 - ratio) / 0.5 * 30)
    }
}

/// Media y desviación típica muestral.
struct Statistics {
    let mean: Double
    let standardDeviation: Double

    init(_ values: [Double]) {
        let count = Double(values.count)
        let average = count > 0 ? values.reduce(0, +) / count : 0
        mean = average
        if values.count > 1 {
            let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / (count - 1)
            standardDeviation = variance.squareRoot()
        } else {
            standardDeviation = 0
        }
    }
}
