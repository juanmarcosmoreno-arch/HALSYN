import Foundation

/// Evolución del corredor: lo que se observa en tus datos y lo que estima el
/// modelo, separados. Todo se calcula con los datos disponibles **hasta**
/// cada fecha (sin usar información posterior).
public struct RunnerProgress: Hashable, Sendable {
    /// Punto semanal del modelo de rendimiento.
    public struct ModelPoint: Hashable, Identifiable, Sendable {
        public let date: Date
        public let vdot: Double
        public let fiveK: TimeInterval
        /// Incertidumbre del modelo ese día (puntos de VDOT).
        public var uncertainty: Double = RacePerformanceModel.minimumUncertainty
        /// Tests y competiciones que lo respaldan.
        public var officialCount: Int = 0
        public var id: Date { date }
    }

    /// Semana de entrenamiento (lunes a domingo).
    public struct Week: Hashable, Identifiable, Sendable {
        public let start: Date
        public let distance: Double
        public let minutes: Double
        public let runs: Int
        /// Minutos por tipo de esfuerzo (suave / moderado / fuerte+).
        public let easyMinutes: Double
        public let moderateMinutes: Double
        public let hardMinutes: Double
        public let unknownMinutes: Double
        public var id: Date { start }
        public var hardShare: Double? {
            let known = easyMinutes + moderateMinutes + hardMinutes
            return known > 0 ? hardMinutes / known : nil
        }
    }

    /// Mejor tiempo observado cerca de una distancia (llevado a la distancia exacta).
    public struct BestEffort: Hashable, Identifiable, Sendable {
        public let distance: RaceDistance
        public let time: TimeInterval
        public let date: Date
        public var id: Double { distance.rawValue }
    }

    /// FC estimada a un ritmo de referencia en un período (Theil–Sen ritmo → FC).
    public struct ComparableHeartRate: Hashable, Identifiable, Sendable {
        public let periodStart: Date
        public let heartRate: Double
        public let runs: Int
        public var id: Date { periodStart }
    }

    public let modelPoints: [ModelPoint]
    public let weeks: [Week]
    public let bestEfforts: [BestEffort]
    /// Ritmo de referencia (s/km) para comparar la FC entre períodos.
    public let referencePace: Double?
    public let comparableHeartRate: [ComparableHeartRate]

    /// Distancias que se buscan en tus carreras: ±1 % por debajo a +6 % por encima.
    public static let bestEffortRange = 0.99...1.06

    public static func build(
        runs allRuns: [WorkoutSummary],
        results: [PerformanceResult],
        maxHeartRate: Double?,
        riegelExponent: Double = RacePerformanceModel.defaultRiegelExponent,
        weeks count: Int,
        today: Date,
        calendar: Calendar
    ) -> RunnerProgress {
        let runs = DataQuality.forPerformance(allRuns.filter(\.activity.isRun))
        let todayStart = calendar.startOfDay(for: today)
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? todayStart

        // 1. Modelo semana a semana (cada punto solo ve los datos hasta ese día).
        var modelPoints: [ModelPoint] = []
        for offset in stride(from: count, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -7 * offset, to: todayStart) else { continue }
            let end = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let visibleRuns = runs.filter { $0.start < end }
            let visibleResults = results.filter { $0.date < end }
            // Cada punto es el final de ese día.
            let endOfDay = end.addingTimeInterval(-1)
            guard let model = RacePerformanceModel.assess(results: visibleResults, runs: visibleRuns, maxHeartRate: maxHeartRate, riegelExponent: riegelExponent, today: endOfDay, calendar: calendar) else { continue }
            modelPoints.append(ModelPoint(date: date, vdot: model.currentVDOT, fiveK: model.predict(5000).time, uncertainty: model.uncertainty, officialCount: model.officialCount))
        }

        // 2. Semanas de entrenamiento.
        let reference = EffortClassifier.referenceMaxHeartRate(configured: maxHeartRate, runs: runs)
        let weeks: [Week] = (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inWeek = runs.filter { $0.start >= start && $0.start < end }
            var easy = 0.0, moderate = 0.0, hard = 0.0, unknown = 0.0
            for run in inWeek {
                let minutes = run.duration / 60
                switch EffortClassifier.classify(run, maxHeartRate: reference) {
                case .easy: easy += minutes
                case .moderate: moderate += minutes
                case .hard, .maximal, .test, .race: hard += minutes
                case .unknown: unknown += minutes
                }
            }
            return Week(start: start, distance: inWeek.compactMap(\.distanceMeters).reduce(0, +), minutes: inWeek.map(\.duration).reduce(0, +) / 60, runs: inWeek.count, easyMinutes: easy, moderateMinutes: moderate, hardMinutes: hard, unknownMinutes: unknown)
        }

        // 3. Mejores tiempos observados (último año).
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: todayStart) ?? todayStart
        let bestEfforts = RaceDistance.allCases.compactMap { target -> BestEffort? in
            let candidates = runs.filter { run in
                guard run.start >= yearAgo, let distance = run.distanceMeters else { return false }
                return bestEffortRange.contains(distance / target.rawValue)
            }
            let best = candidates.min { a, b in
                a.duration / (a.distanceMeters ?? 1) < b.duration / (b.distanceMeters ?? 1)
            }
            guard let best, let distance = best.distanceMeters else { return nil }
            // Se lleva a la distancia exacta con Riegel (la diferencia es pequeña).
            return BestEffort(distance: target, time: RacePerformanceModel.riegel(time: best.duration, from: distance, to: target.rawValue, exponent: riegelExponent), date: best.start)
        }

        // 4. FC a un ritmo comparable, por períodos de 4 semanas.
        let withHeartRate = runs.filter { $0.averageHeartRate != nil && $0.averagePace != nil && $0.duration >= 15 * 60 }
        let paces = withHeartRate.compactMap { $0.averagePace?.secondsPerKilometer }
        let referencePace = RacePerformanceModel.median(paces)
        var comparable: [ComparableHeartRate] = []
        if let referencePace {
            let periods = max(1, count / 4)
            for offset in (0..<periods).reversed() {
                guard let start = calendar.date(byAdding: .weekOfYear, value: -4 * (offset + 1) + 1, to: currentWeek),
                      let end = calendar.date(byAdding: .weekOfYear, value: 4, to: start) else { continue }
                let period = withHeartRate.filter { $0.start >= start && $0.start < end }
                guard let estimate = heartRate(at: referencePace, runs: period) else { continue }
                comparable.append(ComparableHeartRate(periodStart: start, heartRate: estimate, runs: period.count))
            }
        }
        return RunnerProgress(modelPoints: modelPoints, weeks: weeks, bestEfforts: bestEfforts, referencePace: referencePace, comparableHeartRate: comparable)
    }

    /// FC estimada a un ritmo con una recta robusta (Theil–Sen) ritmo → FC.
    /// Necesita 4 carreras o más con ritmos distintos; si el ritmo cae fuera
    /// de los de esas carreras, no se extrapola.
    public static func heartRate(at pace: Double, runs: [WorkoutSummary]) -> Double? {
        let points = runs.compactMap { run -> (x: Double, y: Double)? in
            guard let p = run.averagePace?.secondsPerKilometer, let hr = run.averageHeartRate else { return nil }
            return (p, hr)
        }
        guard points.count >= 4, let low = points.map(\.x).min(), let high = points.map(\.x).max(),
              high - low >= 10, (low...high).contains(pace),
              let slope = RacePerformanceModel.theilSen(points) else { return nil }
        let intercept = RacePerformanceModel.median(points.map { $0.y - slope * $0.x }) ?? 0
        return intercept + slope * pace
    }
}

/// Comparación de un período (4, 8 o 12 semanas) con el anterior de igual largo.
public struct PeriodComparison: Hashable, Sendable {
    public let weeks: Int
    public let weeklyDistance: Double
    public let previousWeeklyDistance: Double
    public let runsPerWeek: Double
    public let previousRunsPerWeek: Double
    public let hardShare: Double?
    public let previousHardShare: Double?
    /// Cambio del 5 km previsto por el modelo (s; negativo = más rápido).
    public let fiveKChange: TimeInterval?
    /// Cambio de la FC a ritmo comparable (lpm; negativo = mejor).
    public let heartRateChange: Double?
    /// Variación normal del modelo en el 5 km (s): lo que se mueve por la
    /// incertidumbre de la forma, sin que cambie nada real.
    public var fiveKNoise: TimeInterval?
    /// Con menos de 3 tests o competiciones, la tendencia es provisional.
    public var isProvisional: Bool = true

    /// El cambio del 5 km supera la variación normal del modelo.
    public var fiveKChangeIsReal: Bool {
        guard let change = fiveKChange, let noise = fiveKNoise else { return false }
        return abs(change) > noise
    }

    public static func compare(_ progress: RunnerProgress, weeks: Int) -> PeriodComparison {
        let recent = Array(progress.weeks.suffix(weeks))
        let previous = Array(progress.weeks.dropLast(weeks).suffix(weeks))
        func perWeek(_ items: [RunnerProgress.Week], _ value: (RunnerProgress.Week) -> Double) -> Double {
            items.isEmpty ? 0 : items.map(value).reduce(0, +) / Double(items.count)
        }
        func share(_ items: [RunnerProgress.Week]) -> Double? {
            let hard = items.map(\.hardMinutes).reduce(0, +)
            let known = items.map { $0.easyMinutes + $0.moderateMinutes + $0.hardMinutes }.reduce(0, +)
            return known > 0 ? hard / known : nil
        }
        var fiveK: TimeInterval?
        var noise: TimeInterval?
        if let last = progress.modelPoints.last,
           let start = progress.modelPoints.dropLast().last(where: { $0.date <= last.date.addingTimeInterval(-Double(weeks) * 7 * 86_400 + 3600) }) {
            fiveK = last.fiveK - start.fiveK
            // Ruido: lo que cambia el 5 km con ±1 σ (combinando los dos extremos).
            let sigma = (last.uncertainty * last.uncertainty + start.uncertainty * start.uncertainty).squareRoot()
            noise = abs(VDOT.raceTime(vdot: last.vdot - sigma, distance: 5000) - VDOT.raceTime(vdot: last.vdot, distance: 5000))
        }
        var heartRate: Double?
        let periods = max(1, weeks / 4)
        if progress.comparableHeartRate.count > periods, let last = progress.comparableHeartRate.last {
            heartRate = last.heartRate - progress.comparableHeartRate[progress.comparableHeartRate.count - 1 - periods].heartRate
        }
        return PeriodComparison(
            weeks: weeks,
            weeklyDistance: perWeek(recent, \.distance),
            previousWeeklyDistance: perWeek(previous, \.distance),
            runsPerWeek: perWeek(recent) { Double($0.runs) },
            previousRunsPerWeek: perWeek(previous) { Double($0.runs) },
            hardShare: share(recent),
            previousHardShare: share(previous),
            fiveKChange: fiveK,
            heartRateChange: heartRate,
            fiveKNoise: noise,
            isProvisional: (progress.modelPoints.last?.officialCount ?? 0) < 3
        )
    }
}
