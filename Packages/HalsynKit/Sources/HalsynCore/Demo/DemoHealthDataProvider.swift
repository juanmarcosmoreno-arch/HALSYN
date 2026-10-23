import Foundation

/// Proveedor de datos sintéticos para el modo demo y para tests.
///
/// - Todos los valores llevan `DataOrigin.demo`.
/// - Son deterministas: el mismo día y la misma semilla producen siempre el mismo
///   valor, sin importar el orden de las consultas.
/// - Los rangos son plausibles para un adulto activo, pero NO son datos de
///   referencia poblacional ni deben usarse como tales.
public struct DemoHealthDataProvider: HealthDataProviding {
    public let mode: DataMode = .demo
    public let seed: UInt64
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(seed: UInt64 = 0x48A15, calendar: Calendar = .halsynGregorian, now: @escaping @Sendable () -> Date = { Date() }) {
        self.seed = seed
        self.calendar = calendar
        self.now = now
    }

    public func authorizationState() async -> HealthAuthorizationState { .notRequired }

    public func requestAuthorization() async throws {}

    public func latest(_ kind: MetricKind, on day: Date) async -> MetricAvailability {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: now()) else { return .noData }
        return .available(MetricReading(kind: kind, value: value(kind, on: start), date: start, origin: .demo))
    }

    public func dailySeries(_ kind: MetricKind, days: Int, endingOn end: Date) async -> MetricSeries {
        MetricSeries(kind: kind, values: series(kind, days: days, endingOn: end), origin: .demo)
    }

    public func recentWorkouts(limit: Int) async -> [WorkoutSummary] {
        let today = calendar.startOfDay(for: now())
        var workouts: [WorkoutSummary] = []
        var offset = 0
        while workouts.count < limit && offset < 120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            var rng = generator(for: day, salt: 0xC0FFEE)
            // Aproximadamente cuatro carreras por semana.
            if Double.random(in: 0..<1, using: &rng) < 0.57 {
                workouts.append(makeRun(on: day, using: &rng))
            }
            offset += 1
        }
        return workouts
    }

    /// Ruta y FC sintéticas (deterministas) para ver el detalle en modo demo.
    /// Recorrido de ejemplo en Djurgården (Estocolmo); siempre etiquetado como demo.
    public func workoutDetail(for workout: WorkoutSummary) async -> WorkoutDetailData {
        guard let distance = workout.distanceMeters, distance > 0, workout.duration > 0 else { return .empty(.demo) }
        var rng = generator(for: workout.start, salt: 0x2047E)
        let center = (latitude: 59.3263, longitude: 18.1157)
        let metersPerDegreeLatitude = 111_195.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(center.latitude * .pi / 180)
        // Bucle irregular de ~2,4 km recorrido las veces necesarias, un punto por segundo.
        // La posición se interpola por longitud de arco para que la distancia de la ruta
        // coincida con la del entrenamiento.
        let loop = Self.demoLoop(length: 2400)
        let speed = distance / workout.duration
        var route: [LocationSample] = []
        var heartRate: [HeartRatePoint] = []
        let average = workout.averageHeartRate ?? 145
        let maximum = workout.maxHeartRate ?? average + 15
        var second = 0.0
        var covered = 0.0
        var drift = 0.0
        while second <= workout.duration {
            // Variación lenta del ritmo (±6 %) para que los parciales no sean idénticos.
            drift = max(-0.06, min(0.06, drift + Double.random(in: -0.004...0.004, using: &rng)))
            covered += second > 0 ? speed * (1 + drift) : 0
            let point = Self.position(on: loop, at: covered)
            let date = workout.start.addingTimeInterval(second)
            route.append(LocationSample(
                latitude: center.latitude + point.north / metersPerDegreeLatitude,
                longitude: center.longitude + point.east / metersPerDegreeLongitude,
                altitude: 12 + 8 * sin(covered / 380),
                horizontalAccuracy: 4,
                verticalAccuracy: 3,
                timestamp: date
            ))
            if Int(second) % 5 == 0 {
                let warmup = min(second / 300, 1)
                let bpm = min(maximum, (average - 25) + 25 * warmup + 6 * sin(second / 240) + Double.random(in: -2...2, using: &rng))
                heartRate.append(HeartRatePoint(date: date, bpm: bpm.rounded()))
            }
            second += 1
        }
        return WorkoutDetailData(route: route, heartRate: heartRate, origin: .demo)
    }

    /// Puntuación calculada por el mismo `HealthScoreEngine` que en modo real,
    /// a partir de las series demo. Sigue llevando el origen `.demo`.
    public func dailyScore(on day: Date) async -> DailyScore? {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: now()) else { return nil }
        return await dailyScores(endingOn: start, days: 1).first { calendar.isDate($0.day, inSameDayAs: start) }
    }

    public func dailyScores(endingOn end: Date, days: Int) async -> [DailyScore] {
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now()))
        return await computeDailyScores(endingOn: last, days: days, calendar: calendar, origin: .demo)
    }

    /// Los datos demo no cambian: el flujo termina inmediatamente.
    public func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    /// Recuperación calculada por el mismo `RecoveryEngine` que en modo real.
    public func recoveryScore(on day: Date) async -> DailyScore? {
        await recoveryEstimates(endingOn: day, days: 1).last?.dailyScore
    }

    public func recoveryEstimates(endingOn end: Date, days: Int) async -> [RecoveryEstimate] {
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now()))
        return await computeRecovery(endingOn: last, days: days, calendar: calendar, origin: .demo)
    }

    /// Noches demo con fases, analizadas con el mismo `SleepAnalysis` que los datos reales.
    /// El tiempo dormido coincide con la serie demo de sueño.
    public func sleepNights(endingOn end: Date, days: Int) async -> [SleepNight] {
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now()))
        guard days > 0 else { return [] }
        let samples = (0..<days).flatMap { offset -> [SleepSample] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: last) else { return [] }
            return sleepSamples(endingOn: day)
        }
        return SleepAnalysis.nights(samples, endingOn: last, days: days, calendar: calendar, origin: .demo)
    }

    /// Hipnograma sintético: ciclos de ~90 min con más sueño profundo al principio
    /// y más REM al final, y despertares breves. Determinista por día.
    func sleepSamples(endingOn day: Date) -> [SleepSample] {
        let start = calendar.startOfDay(for: day)
        var rng = generator(for: start, salt: 0x5EE9)
        let asleepTarget = value(.sleepDuration, on: start) * 3600
        let bedtimeOffset = Double.random(in: -50...45, using: &rng) * 60
        var cursor = start.addingTimeInterval(-60 * 60 + bedtimeOffset) // ~23:00
        var asleep: TimeInterval = 0
        var samples: [SleepSample] = []
        var cycle = 0
        let source = "Apple Watch"
        func add(_ stage: SleepSample.Stage, _ minutes: Double) {
            let seconds = stage.isAsleep ? min(minutes * 60, asleepTarget - asleep) : minutes * 60
            guard seconds > 0 else { return }
            samples.append(SleepSample(start: cursor, end: cursor.addingTimeInterval(seconds), stage: stage, sourceName: source))
            cursor = cursor.addingTimeInterval(seconds)
            if stage.isAsleep { asleep += seconds }
        }
        while asleep < asleepTarget - 1 {
            let late = Double(cycle) / 4
            add(.asleepCore, Double.random(in: 18...30, using: &rng))
            add(.asleepDeep, max(4, (1 - late) * Double.random(in: 18...34, using: &rng)))
            add(.asleepCore, Double.random(in: 14...24, using: &rng))
            add(.asleepREM, 8 + late * Double.random(in: 10...24, using: &rng))
            if Double.random(in: 0..<1, using: &rng) < 0.45 {
                add(.awake, Double.random(in: 2...9, using: &rng))
            }
            cycle += 1
        }
        return samples
    }

    public func goals() async -> [Goal] {
        let today = calendar.startOfDay(for: now())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let elapsedDays = max(1, (calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0) + 1)
        let weekDays = (0..<elapsedDays).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let weeklyExercise = weekDays.map { value(.exerciseTime, on: $0) }.reduce(0, +)
        let weeklyRunMeters = weekDays.reduce(0.0) { total, day in
            var rng = generator(for: day, salt: 0xC0FFEE)
            guard Double.random(in: 0..<1, using: &rng) < 0.57 else { return total }
            return total + (makeRun(on: day, using: &rng).distanceMeters ?? 0)
        }
        return [
            Goal(title: "Caminar 8.000 pasos", metric: .steps, target: 8000, current: value(.steps, on: today), period: .daily, origin: .demo),
            Goal(title: "150 min de actividad", metric: .exerciseTime, target: 150, current: weeklyExercise, period: .weekly, origin: .demo),
            Goal(title: "Dormir 7 h o más", metric: .sleepDuration, target: 7, current: value(.sleepDuration, on: today), period: .daily, origin: .demo),
            Goal(title: "Correr 25 km", metric: .walkingRunningDistance, target: 25_000, current: weeklyRunMeters, period: .weekly, origin: .demo),
        ]
    }

    // MARK: - Generación

    func series(_ kind: MetricKind, days: Int, endingOn end: Date) -> [DailyValue] {
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now()))
        return (0..<max(days, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: last).map { DailyValue(day: $0, value: value(kind, on: $0)) }
        }
    }

    func value(_ kind: MetricKind, on day: Date) -> Double {
        var rng = generator(for: day, salt: UInt64(MetricKind.allCases.firstIndex(of: kind) ?? 0) &+ 1)
        let noise = Double.random(in: -1...1, using: &rng)
        let slowTrend = sin(Double(dayNumber(day)) / 9)
        switch kind {
        // Los fines de semana se camina algo más (patrón semanal visible en INSIKT).
        case .steps: return (8300 + 2200 * noise + (isWeekend(day) ? 1400 : 0)).rounded()
        case .walkingRunningDistance: return 6400 + 2200 * noise
        case .activeEnergy: return 540 + 160 * noise
        case .exerciseTime: return max(0, 36 + 22 * noise).rounded()
        case .sleepDuration: return 7.4 + 0.7 * noise
        // Relaciones plausibles para la demo: dormir más se asocia a más HRV y menos
        // FC en reposo; un día de mucho ejercicio, a menos HRV al día siguiente.
        case .restingHeartRate: return (54 + 2 * slowTrend + 2 * noise - 1.5 * (value(.sleepDuration, on: day) - 7.4)).rounded()
        case .heartRateVariability:
            let sleepEffect = 9 * (value(.sleepDuration, on: day) - 7.4)
            let loadEffect = -0.08 * (value(.exerciseTime, on: previousDay(day)) - 36)
            return (62 + 6 * slowTrend + 6 * noise + sleepEffect + loadEffect).rounded()
        case .heartRate: return (68 + 6 * noise).rounded()
        case .respiratoryRate: return 14.6 + 0.6 * noise
        case .vo2Max: return 47.8 + 0.6 * slowTrend + 0.2 * noise
        case .oxygenSaturation: return 0.97 + 0.01 * noise
        }
    }

    private func makeRun(on day: Date, using rng: inout SeededRandomNumberGenerator) -> WorkoutSummary {
        let distance = Double.random(in: 4200...14500, using: &rng)
        let paceSeconds = Double.random(in: 285...345, using: &rng)
        let startHour = Double.random(in: 6.5...19.5, using: &rng)
        let average = Double.random(in: 138...158, using: &rng).rounded()
        return WorkoutSummary(
            id: UUID(uuid: uuidBytes(for: day)),
            activity: .outdoorRun,
            start: day.addingTimeInterval(startHour * 3600),
            duration: distance / 1000 * paceSeconds,
            distanceMeters: distance,
            averageHeartRate: average,
            maxHeartRate: average + Double.random(in: 12...24, using: &rng).rounded(),
            activeEnergyKilocalories: (distance / 1000 * 68).rounded(),
            averageCadence: Double.random(in: 162...178, using: &rng).rounded(),
            origin: .demo
        )
    }

    /// Polilínea cerrada (metros norte/este) con su longitud acumulada, escalada a `length`.
    private static func demoLoop(length: Double) -> [(north: Double, east: Double, along: Double)] {
        let raw: [(Double, Double)] = (0...360).map { degree in
            let angle = Double(degree) * .pi / 180
            let wobble = 1 + 0.18 * sin(angle * 3)
            return (wobble * sin(angle), 1.6 * wobble * (1 - cos(angle)))
        }
        var perimeter = 0.0
        for index in 1..<raw.count {
            perimeter += hypot(raw[index].0 - raw[index - 1].0, raw[index].1 - raw[index - 1].1)
        }
        let scale = length / perimeter
        var along = 0.0
        var result: [(north: Double, east: Double, along: Double)] = []
        for index in raw.indices {
            if index > 0 {
                along += hypot(raw[index].0 - raw[index - 1].0, raw[index].1 - raw[index - 1].1) * scale
            }
            result.append((raw[index].0 * scale, raw[index].1 * scale, along))
        }
        return result
    }

    private static func position(on loop: [(north: Double, east: Double, along: Double)], at distance: Double) -> (north: Double, east: Double) {
        guard let total = loop.last?.along, total > 0 else { return (0, 0) }
        let target = distance.truncatingRemainder(dividingBy: total)
        let upper = loop.firstIndex { $0.along >= target } ?? loop.count - 1
        guard upper > 0 else { return (loop[0].north, loop[0].east) }
        let a = loop[upper - 1], b = loop[upper]
        let fraction = b.along > a.along ? (target - a.along) / (b.along - a.along) : 0
        return (a.north + (b.north - a.north) * fraction, a.east + (b.east - a.east) * fraction)
    }

    private func isWeekend(_ day: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    private func previousDay(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: day) ?? day
    }

    private func dayNumber(_ day: Date) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return (components.year ?? 0) * 372 + (components.month ?? 0) * 31 + (components.day ?? 0)
    }

    private func generator(for day: Date, salt: UInt64) -> SeededRandomNumberGenerator {
        SeededRandomNumberGenerator(seed: seed ^ (UInt64(dayNumber(day)) &* 0x100_0000_01B3) ^ (salt &* 0x9E37_79B9))
    }

    private func uuidBytes(for day: Date) -> uuid_t {
        var rng = generator(for: day, salt: 0x1D)
        let a = rng.next(), b = rng.next()
        func byte(_ v: UInt64, _ i: UInt64) -> UInt8 { UInt8((v >> (i * 8)) & 0xFF) }
        return (byte(a, 0), byte(a, 1), byte(a, 2), byte(a, 3), byte(a, 4), byte(a, 5), byte(a, 6), byte(a, 7),
                byte(b, 0), byte(b, 1), byte(b, 2), byte(b, 3), byte(b, 4), byte(b, 5), byte(b, 6), byte(b, 7))
    }
}
