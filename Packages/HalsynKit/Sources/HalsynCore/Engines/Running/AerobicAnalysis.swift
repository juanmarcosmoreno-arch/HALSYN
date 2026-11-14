import Foundation

/// Lo que aporta una carrera al análisis aeróbico: velocidad media por franja
/// de pulso en sus tramos estables, su eficiencia y su desacople.
public struct AerobicRunObservation: Codable, Hashable, Identifiable, Sendable {
    /// Velocidad en una franja de 5 lpm.
    public struct Bin: Codable, Hashable, Sendable {
        /// Centro de la franja (lpm).
        public let heartRate: Double
        /// Velocidad media ponderada por tiempo (m/min).
        public let speed: Double
        public let seconds: Double
    }

    public let id: UUID
    public let date: Date
    public let bins: [Bin]
    /// Metros por minuto por latido en los tramos estables (más = más eficiente).
    public let efficiency: Double?
    /// Segundos de tramos estables usados.
    public let steadySeconds: Double
    /// Desacople ritmo:pulso (%, positivo = el pulso sube al final), solo en
    /// carreras continuas y regulares de 30 min o más.
    public let decoupling: Double?
    public let movingSeconds: Double
}

/// Ritmo estimado a un pulso fijo en un período.
public struct FixedHeartRatePace: Hashable, Sendable {
    public let heartRate: Double
    /// Ritmo estimado (s/km) y su intervalo del 95 %.
    public let pace: Double
    public let fastest: Double
    public let slowest: Double
    public let runs: Int
    public let steadyMinutes: Double
    /// Pulsos observados en el período (de la franja más baja a la más alta con datos).
    public let observedRange: ClosedRange<Double>
}

/// Cambio del ritmo a pulso fijo entre dos períodos.
public struct FixedHeartRateTrend: Hashable, Sendable {
    public enum Verdict: String, Hashable, Sendable {
        /// Más rápido al mismo pulso, más allá de la incertidumbre.
        case faster
        /// Más lento al mismo pulso, más allá de la incertidumbre.
        case slower
        /// La diferencia cabe en la incertidumbre.
        case unclear
    }

    public let current: FixedHeartRatePace
    public let previous: FixedHeartRatePace?
    /// s/km; positivo = ahora más rápido.
    public let change: Double?
    public let verdict: Verdict?
}

/// Por qué no se pudo estimar algo (nunca se rellena con valores inventados).
public enum AerobicUnavailable: String, Hashable, Sendable {
    /// Menos de 3 carreras con tramos estables (al aire libre, con GPS y pulso).
    case notEnoughRuns
    /// Ese pulso no se observó en el período: no se extrapola.
    case outsideObservedRange
    /// La relación pulso–velocidad no sube con el pulso (datos contradictorios).
    case noRelationship
}

/// Promedio de un indicador en una ventana y su cambio.
public struct AerobicWindow: Hashable, Sendable {
    public let days: Int?
    public let mean: Double
    public let runs: Int
}

public struct EfficiencySummary: Hashable, Sendable {
    public let windows: [AerobicWindow]
    /// Cambio de los últimos 28 días frente a los 28 anteriores (%).
    public let change28: Double?
    /// El cambio supera la variación habitual entre carreras.
    public let changeIsClear: Bool
}

public struct DecouplingSummary: Hashable, Sendable {
    public let latest: DailyValue
    /// Mediana de los últimos 28 días.
    public let median28: Double?
    public let runs28: Int
    public let series: [DailyValue]
}

/// Capacidad aeróbica: ¿corres más rápido con el mismo pulso?
///
/// **Tramos estables** (de los de 200 m del análisis de la carrera):
/// - después del calentamiento (15 % del tiempo, como mucho 10 min);
/// - completos, con pulso y velocidad plausibles (100–400 m/min, 90–210 lpm);
/// - sin aceleraciones: el ritmo se aparta menos de un 8 % de la media de los
///   tramos vecinos;
/// - casi llanos (desnivel neto ≤ 3 %) cuando hay altitud;
/// - el pulso del tramo se toma **30 s después** (el corazón tarda en responder
///   a un cambio de ritmo).
///
/// **Ritmo a pulso fijo**: con las franjas de 5 lpm de todas las carreras del
/// período, recta velocidad = a + b × pulso por mínimos cuadrados ponderados
/// por tiempo. Solo se estima dentro de los pulsos observados (no se
/// extrapola), con 3 carreras o más. La incertidumbre suma la de la recta y la
/// variación entre carreras (cada carrera cuenta como una observación, no cada
/// tramo, porque los tramos de una misma carrera no son independientes).
///
/// **Eficiencia** = velocidad (m/min) ÷ pulso (lpm) en los tramos estables.
/// Un cambio cuenta como claro si supera 1,96 errores estándar.
///
/// **Desacople** = 100 × (EF₁ − EF₂) ÷ EF₁ entre la primera y la segunda mitad
/// tras el calentamiento (convención de Friel: positivo = el pulso sube al
/// final). Solo en carreras de 30 min o más con ritmo regular (variación entre
/// tramos ≤ 8 %).
///
/// El calor, la hidratación, el cansancio y el terreno también lo cambian: son
/// indicadores orientativos, no un diagnóstico.
public enum AerobicAnalysis {
    public static let version = "1.0"
    public static let heartRateLag: TimeInterval = 30
    public static let binWidth = 5.0
    public static let maximumSegmentDeviation = 0.08
    public static let maximumGrade = 0.03
    public static let minimumRuns = 3
    public static let minimumDecouplingTime: TimeInterval = 30 * 60
    public static let maximumPaceVariability = 8.0
    public static let windowDays = 28
    /// El período anterior para comparar termina 8 semanas antes de hoy.
    public static let comparisonGapDays = 56
    public static let targets: [Double] = [130, 140, 150, 160]

    // MARK: Por carrera

    public static func observe(id: UUID, date: Date, route: [LocationSample], heartRate: [HeartRatePoint]) -> AerobicRunObservation? {
        guard let insights = RunAnalyzer.analyze(route: route, heartRate: heartRate) else { return nil }
        let pulse = heartRate.filter { $0.bpm > 0 }.sorted { $0.date < $1.date }
        guard !pulse.isEmpty else { return nil }
        let segments = insights.segments
        var elapsed: TimeInterval = 0
        var steady: [(heartRate: Double, speed: Double, seconds: Double)] = []
        for (index, segment) in segments.enumerated() {
            defer { elapsed += segment.duration }
            guard elapsed >= insights.warmup,
                  segment.distance >= RunAnalyzer.segmentLength * 0.8, segment.duration > 0,
                  let first = segment.points.first?.timestamp, let last = segment.points.last?.timestamp else { continue }
            let speed = segment.distance / segment.duration * 60
            guard (100...400).contains(speed) else { continue }
            // Sin aceleraciones: frente a la media de los tramos vecinos.
            let neighbours = [index - 1, index + 1].filter { segments.indices.contains($0) }.map { segments[$0] }.filter { $0.duration > 0 }
            guard !neighbours.isEmpty else { continue }
            let neighbourSpeed = neighbours.map { $0.distance / $0.duration * 60 }.reduce(0, +) / Double(neighbours.count)
            guard abs(speed - neighbourSpeed) / neighbourSpeed <= maximumSegmentDeviation else { continue }
            // Casi llano.
            if let startAltitude = segment.points.first?.altitude, let endAltitude = segment.points.last?.altitude,
               abs(endAltitude - startAltitude) / segment.distance > maximumGrade { continue }
            // Pulso con 30 s de retraso.
            guard let bpm = RunAnalyzer.average(pulse, from: first.addingTimeInterval(heartRateLag), to: last.addingTimeInterval(heartRateLag)),
                  (90...210).contains(bpm) else { continue }
            steady.append((bpm, speed, segment.duration))
        }
        let seconds = steady.map(\.seconds).reduce(0, +)
        var grouped: [Double: (speedSeconds: Double, seconds: Double)] = [:]
        for item in steady {
            let center = (item.heartRate / binWidth).rounded() * binWidth
            let current = grouped[center] ?? (0, 0)
            grouped[center] = (current.speedSeconds + item.speed * item.seconds, current.seconds + item.seconds)
        }
        let bins = grouped.map { AerobicRunObservation.Bin(heartRate: $0.key, speed: $0.value.speedSeconds / $0.value.seconds, seconds: $0.value.seconds) }
            .sorted { $0.heartRate < $1.heartRate }
        let efficiency: Double? = seconds > 0
            ? steady.map { $0.speed / $0.heartRate * $0.seconds }.reduce(0, +) / seconds
            : nil
        let regular = (insights.paceVariability ?? .infinity) <= maximumPaceVariability
        let decoupling = insights.movingTime >= minimumDecouplingTime && regular ? insights.decoupling : nil
        return AerobicRunObservation(id: id, date: date, bins: bins, efficiency: efficiency, steadySeconds: seconds, decoupling: decoupling, movingSeconds: insights.movingTime)
    }

    // MARK: Ritmo a pulso fijo

    public static func paceAt(_ heartRate: Double, observations: [AerobicRunObservation], from start: Date, to end: Date) -> Result<FixedHeartRatePace, AerobicUnavailableError> {
        let runs = observations.filter { $0.date >= start && $0.date <= end && !$0.bins.isEmpty }
        guard runs.count >= minimumRuns else { return .failure(AerobicUnavailableError(reason: .notEnoughRuns)) }
        let points = runs.flatMap { run in run.bins.map { (run: run.id, x: $0.heartRate, y: $0.speed, w: $0.seconds) } }
        let total = points.map(\.w).reduce(0, +)
        guard total > 0 else { return .failure(AerobicUnavailableError(reason: .notEnoughRuns)) }
        // Solo dentro de lo observado (franjas con al menos 1 min).
        let observed = points.filter { $0.w >= 60 }.map(\.x)
        guard let low = observed.min(), let high = observed.max() else { return .failure(AerobicUnavailableError(reason: .notEnoughRuns)) }
        guard heartRate >= low - binWidth / 2, heartRate <= high + binWidth / 2 else {
            return .failure(AerobicUnavailableError(reason: .outsideObservedRange))
        }
        let meanX = points.map { $0.x * $0.w }.reduce(0, +) / total
        let meanY = points.map { $0.y * $0.w }.reduce(0, +) / total
        let sxx = points.map { $0.w * ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        let sxy = points.map { $0.w * ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +)
        // Con pulsos parecidos la pendiente no se puede estimar (o sale al revés):
        // entonces, la velocidad media de las franjas a ±5 lpm de ese pulso.
        let fitted = sxx > 1e-6 ? sxy / sxx : 0
        let useLine = sxx > 1e-6 && fitted > 0
        let local = points.filter { abs($0.x - heartRate) <= binWidth }
        if !useLine && local.isEmpty { return .failure(AerobicUnavailableError(reason: .noRelationship)) }
        let slope = useLine ? fitted : 0
        let localWeight = local.map(\.w).reduce(0, +)
        let center = useLine ? meanX : local.map { $0.x * $0.w }.reduce(0, +) / localWeight
        let level = useLine ? meanY : local.map { $0.y * $0.w }.reduce(0, +) / localWeight
        let used = useLine ? points : local
        let usedWeight = useLine ? total : localWeight
        let speed = level + slope * (heartRate - center)
        guard speed > 0 else { return .failure(AerobicUnavailableError(reason: .noRelationship)) }

        // Incertidumbre: cada carrera, una observación (residuo medio por carrera).
        var runResiduals: [Double] = []
        for run in runs {
            let own = used.filter { $0.run == run.id }
            let weight = own.map(\.w).reduce(0, +)
            guard weight > 0 else { continue }
            runResiduals.append(own.map { ($0.y - (level + slope * ($0.x - center))) * $0.w }.reduce(0, +) / weight)
        }
        let n = Double(max(runResiduals.count, 1))
        let mean = runResiduals.reduce(0, +) / n
        let variance = n > 1 ? runResiduals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1) : 0
        // Pendiente con n efectivo = carreras: su varianza escala con (puntos / carreras).
        let residualVariance = used.map { $0.w * pow($0.y - (level + slope * ($0.x - center)), 2) }.reduce(0, +) / usedWeight
        let slopeVariance = useLine ? residualVariance / sxx * total / n / max(n - 1, 1) : 0
        let standardError = (variance / n + slopeVariance * pow(heartRate - center, 2)).squareRoot()
        let lowSpeed = max(speed - 1.96 * standardError, 1)
        let highSpeed = speed + 1.96 * standardError
        return .success(FixedHeartRatePace(
            heartRate: heartRate,
            pace: 60_000 / speed,
            fastest: 60_000 / highSpeed,
            slowest: 60_000 / lowSpeed,
            runs: runs.count,
            steadyMinutes: total / 60,
            observedRange: low...high
        ))
    }

    /// Ahora (últimos 28 días) frente al mismo pulso 8 semanas antes.
    public static func trend(at heartRate: Double, observations: [AerobicRunObservation], today: Date, calendar: Calendar) -> Result<FixedHeartRateTrend, AerobicUnavailableError> {
        let end = today
        let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: today)) ?? today
        switch paceAt(heartRate, observations: observations, from: start, to: end) {
        case let .failure(error):
            return .failure(error)
        case let .success(current):
            let previousEnd = calendar.date(byAdding: .day, value: -comparisonGapDays, to: calendar.startOfDay(for: today)) ?? today
            let previousStart = calendar.date(byAdding: .day, value: -windowDays, to: previousEnd) ?? previousEnd
            guard case let .success(previous) = paceAt(heartRate, observations: observations, from: previousStart, to: previousEnd) else {
                return .success(FixedHeartRateTrend(current: current, previous: nil, change: nil, verdict: nil))
            }
            let change = previous.pace - current.pace
            // Errores estándar aproximados desde los intervalos del 95 %.
            let currentSE = (current.slowest - current.fastest) / (2 * 1.96)
            let previousSE = (previous.slowest - previous.fastest) / (2 * 1.96)
            let threshold = 1.96 * (currentSE * currentSE + previousSE * previousSE).squareRoot()
            let verdict: FixedHeartRateTrend.Verdict = abs(change) <= threshold ? .unclear : (change > 0 ? .faster : .slower)
            return .success(FixedHeartRateTrend(current: current, previous: previous, change: change, verdict: verdict))
        }
    }

    // MARK: Eficiencia y desacople

    public static func efficiency(_ observations: [AerobicRunObservation], today: Date, calendar: Calendar) -> EfficiencySummary? {
        let valued = observations.compactMap { run in run.efficiency.map { (date: run.date, value: $0) } }
        guard valued.count >= minimumRuns else { return nil }
        let startOfToday = calendar.startOfDay(for: today)
        func window(_ days: Int?) -> AerobicWindow? {
            let items = days.map { days in valued.filter { $0.date >= (calendar.date(byAdding: .day, value: -days, to: startOfToday) ?? today) && $0.date <= today } } ?? valued
            guard !items.isEmpty else { return nil }
            return AerobicWindow(days: days, mean: items.map(\.value).reduce(0, +) / Double(items.count), runs: items.count)
        }
        let windows = [7, 28, 90, nil].compactMap(window)
        let recentStart = calendar.date(byAdding: .day, value: -windowDays, to: startOfToday) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -2 * windowDays, to: startOfToday) ?? today
        let recent = valued.filter { $0.date >= recentStart && $0.date <= today }.map(\.value)
        let previous = valued.filter { $0.date >= previousStart && $0.date < recentStart }.map(\.value)
        guard recent.count >= 2, previous.count >= 2 else { return EfficiencySummary(windows: windows, change28: nil, changeIsClear: false) }
        func stats(_ values: [Double]) -> (mean: Double, variance: Double) {
            let mean = values.reduce(0, +) / Double(values.count)
            return (mean, values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1))
        }
        let a = stats(recent), b = stats(previous)
        let change = (a.mean - b.mean) / b.mean * 100
        let standardError = (a.variance / Double(recent.count) + b.variance / Double(previous.count)).squareRoot()
        return EfficiencySummary(windows: windows, change28: change, changeIsClear: abs(a.mean - b.mean) > 1.96 * standardError)
    }

    public static func decoupling(_ observations: [AerobicRunObservation], today: Date, calendar: Calendar) -> DecouplingSummary? {
        let valued = observations.compactMap { run in run.decoupling.map { DailyValue(day: run.date, value: $0) } }.sorted { $0.day < $1.day }
        guard let last = valued.last else { return nil }
        let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: today)) ?? today
        let recent = valued.filter { $0.day >= start }.map(\.value).sorted()
        let median: Double? = recent.isEmpty ? nil : (recent.count % 2 == 1 ? recent[recent.count / 2] : (recent[recent.count / 2 - 1] + recent[recent.count / 2]) / 2)
        return DecouplingSummary(latest: last, median28: median, runs28: recent.count, series: valued)
    }
}

/// Error con el motivo (para `Result`).
public struct AerobicUnavailableError: Error, Hashable, Sendable {
    public let reason: AerobicUnavailable
}
