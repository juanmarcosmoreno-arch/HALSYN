import Foundation

/// Una métrica de técnica de carrera.
public enum RunningDynamicsMetric: String, CaseIterable, Hashable, Identifiable, Sendable {
    case cadence
    case strideLength
    case groundContactTime
    case verticalOscillation
    case power
    /// Indicador indirecto: velocidad por vatio (m/min por W).
    case speedPerWatt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cadence: "Cadencia"
        case .strideLength: "Longitud de zancada"
        case .groundContactTime: "Tiempo de contacto con el suelo"
        case .verticalOscillation: "Oscilación vertical"
        case .power: "Potencia de carrera"
        case .speedPerWatt: "Velocidad por vatio"
        }
    }

    public var unit: String {
        switch self {
        case .cadence: "ppm"
        case .strideLength: "m"
        case .groundContactTime: "ms"
        case .verticalOscillation: "cm"
        case .power: "W"
        case .speedPerWatt: "m/min por W"
        }
    }

    public var fractionDigits: Int {
        switch self {
        case .strideLength, .speedPerWatt: 2
        case .verticalOscillation: 1
        default: 0
        }
    }

    func value(_ run: WorkoutSummary) -> Double? {
        switch self {
        case .cadence: return run.averageCadence.flatMap { (120...240).contains($0) ? $0 : nil }
        case .strideLength: return run.dynamics?.strideLength.flatMap { (0.4...3).contains($0) ? $0 : nil }
        case .groundContactTime: return run.dynamics?.groundContactTime.flatMap { (100...500).contains($0) ? $0 : nil }
        case .verticalOscillation: return run.dynamics?.verticalOscillation.flatMap { (2...20).contains($0) ? $0 : nil }
        case .power: return run.dynamics?.power.flatMap { (50...800).contains($0) ? $0 : nil }
        case .speedPerWatt:
            guard let power = RunningDynamicsMetric.power.value(run), let speed = RunningDynamicsAnalysis.speed(run) else { return nil }
            return speed / power
        }
    }
}

/// Una métrica en un período, comparada a igual velocidad con 8 semanas antes.
public struct RunningDynamicsSummary: Hashable, Identifiable, Sendable {
    public enum Change: String, Hashable, Sendable {
        case higher, lower, unclear
    }

    public let metric: RunningDynamicsMetric
    /// Media de los últimos 28 días (tal cual, sin ajustar).
    public let recentMean: Double
    public let recentRuns: Int
    /// Diferencia frente a los 28 días que terminan 8 semanas antes, a igual
    /// velocidad (ajustada con la recta métrica–velocidad de todas tus carreras).
    public let adjustedChange: Double?
    public let change: Change?
    /// Serie por carrera (fecha, valor).
    public let series: [DailyValue]

    public var id: RunningDynamicsMetric { metric }
}

/// Técnica de carrera a partir de las medias que guarda el Apple Watch.
///
/// - Solo carreras con distancia y duración (cadencia: pasos ÷ minutos;
///   zancada, contacto, oscilación y potencia: medias del entrenamiento).
///   Valores fuera de rangos físicos se descartan.
/// - **A igual velocidad**: la cadencia, la zancada o el contacto cambian solos
///   al correr más rápido. Con todas tus carreras se ajusta una recta
///   métrica = a + b × velocidad y se comparan los residuos medios de los
///   últimos 28 días con los de los 28 días que terminan 8 semanas antes. Hay
///   cambio si supera 1,96 errores estándar.
/// - Lenguaje neutro: «más alta» o «más baja», nunca «mejor». No hay una
///   técnica óptima universal.
/// - **Velocidad por vatio** es un indicador indirecto (no mide la economía
///   metabólica, que necesita análisis de gases).
public enum RunningDynamicsAnalysis {
    public static let version = "1.0"
    public static let windowDays = 28
    public static let comparisonGapDays = 56
    public static let minimumRuns = 3

    /// Velocidad media (m/min).
    static func speed(_ run: WorkoutSummary) -> Double? {
        guard let distance = run.distanceMeters, distance >= 1000, run.duration > 0 else { return nil }
        let speed = distance / run.duration * 60
        return (100...400).contains(speed) ? speed : nil
    }

    public static func summaries(_ runs: [WorkoutSummary], today: Date, calendar: Calendar) -> [RunningDynamicsSummary] {
        RunningDynamicsMetric.allCases.compactMap { summary($0, runs: runs, today: today, calendar: calendar) }
    }

    public static func summary(_ metric: RunningDynamicsMetric, runs: [WorkoutSummary], today: Date, calendar: Calendar) -> RunningDynamicsSummary? {
        let points = runs.filter(\.activity.isRun).compactMap { run -> (date: Date, x: Double, y: Double)? in
            guard let x = speed(run), let y = metric.value(run) else { return nil }
            return (run.start, x, y)
        }.sorted { $0.date < $1.date }
        let start = calendar.startOfDay(for: today)
        let recentStart = calendar.date(byAdding: .day, value: -windowDays, to: start) ?? today
        let recent = points.filter { $0.date >= recentStart && $0.date <= today }
        guard recent.count >= minimumRuns else { return nil }
        let recentMean = recent.map(\.y).reduce(0, +) / Double(recent.count)
        let series = points.map { DailyValue(day: $0.date, value: $0.y) }

        let previousEnd = calendar.date(byAdding: .day, value: -comparisonGapDays, to: start) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -windowDays, to: previousEnd) ?? previousEnd
        let previous = points.filter { $0.date >= previousStart && $0.date < previousEnd }
        guard previous.count >= minimumRuns else {
            return RunningDynamicsSummary(metric: metric, recentMean: recentMean, recentRuns: recent.count, adjustedChange: nil, change: nil, series: series)
        }
        // Recta métrica–velocidad con todas las carreras.
        let n = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        let sxx = points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        let slope = sxx > 1e-9 ? points.map { ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +) / sxx : 0
        func residuals(_ items: [(date: Date, x: Double, y: Double)]) -> [Double] {
            items.map { $0.y - (meanY + slope * ($0.x - meanX)) }
        }
        let a = residuals(recent), b = residuals(previous)
        func stats(_ values: [Double]) -> (mean: Double, variance: Double) {
            let mean = values.reduce(0, +) / Double(values.count)
            return (mean, values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(values.count - 1, 1)))
        }
        let ra = stats(a), rb = stats(b)
        let difference = ra.mean - rb.mean
        let standardError = (ra.variance / Double(a.count) + rb.variance / Double(b.count)).squareRoot()
        let change: RunningDynamicsSummary.Change = abs(difference) <= 1.96 * standardError ? .unclear : (difference > 0 ? .higher : .lower)
        return RunningDynamicsSummary(metric: metric, recentMean: recentMean, recentRuns: recent.count, adjustedChange: difference, change: change, series: series)
    }
}
