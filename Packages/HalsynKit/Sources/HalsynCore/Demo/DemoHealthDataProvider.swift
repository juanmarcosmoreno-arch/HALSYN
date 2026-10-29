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

    /// Salidas en bici sintéticas: unas dos por semana, algunas en rodillo y
    /// algunas con medidor de potencia. Siempre con origen `.demo`.
    public func recentRides(limit: Int) async -> [WorkoutSummary] {
        let today = calendar.startOfDay(for: now())
        var rides: [WorkoutSummary] = []
        var offset = 0
        while rides.count < limit && offset < 180 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            var rng = generator(for: day, salt: 0xB1CE)
            if Double.random(in: 0..<1, using: &rng) < 0.3 {
                rides.append(makeRide(on: day, using: &rng))
            }
            offset += 1
        }
        return rides
    }

    /// Recuperaciones sintéticas después de algunas carreras demo, mejorando
    /// poco a poco (unos 22 lpm hace 3 meses, unos 28 ahora). Siempre `.demo`.
    public func heartRateRecoveries(days: Int) async -> [RecoveryReading] {
        let runs = await recentWorkouts(limit: 120)
        let today = calendar.startOfDay(for: now())
        let start = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        return runs
            .filter { $0.start >= start }
            .enumerated()
            .compactMap { index, run -> RecoveryReading? in
                // Una de cada dos carreras se midió.
                guard index % 2 == 0 else { return nil }
                var rng = generator(for: run.start, salt: 0x4E4E)
                let age = Double(calendar.dateComponents([.day], from: run.start, to: today).day ?? 0)
                let oneMinute = (28 - age / 15 + Double.random(in: -3...3, using: &rng)).rounded()
                let end = (run.maxHeartRate ?? 170) - Double.random(in: 0...6, using: &rng).rounded()
                return RecoveryReading(
                    date: run.end,
                    oneMinute: oneMinute,
                    twoMinutes: (oneMinute * 1.6 + Double.random(in: -3...3, using: &rng)).rounded(),
                    endHeartRate: end,
                    origin: .demo
                )
            }
            .sorted { $0.date < $1.date }
    }

    public func ridePower(for workout: WorkoutSummary) async -> [PowerSample] {
        demoPower(for: workout)
    }

    /// Ruta y FC sintéticas (deterministas) para ver el detalle en modo demo.
    /// Recorrido de ejemplo en Djurgården (Estocolmo); siempre etiquetado como demo.
    public func workoutDetail(for workout: WorkoutSummary) async -> WorkoutDetailData {
        guard workout.duration > 0 else { return .empty(.demo) }
        if workout.activity == .indoorRide {
            // En rodillo no hay ruta: solo FC y potencia.
            return WorkoutDetailData(heartRate: demoHeartRate(for: workout), power: demoPower(for: workout), origin: .demo)
        }
        guard let distance = workout.distanceMeters, distance > 0 else { return .empty(.demo) }
        var rng = generator(for: workout.start, salt: 0x2047E)
        let center = (latitude: 59.3263, longitude: 18.1157)
        let metersPerDegreeLatitude = 111_195.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(center.latitude * .pi / 180)
        // Bucle irregular de ~2,4 km (12 km en bici) recorrido las veces necesarias, un punto por segundo.
        // La posición se interpola por longitud de arco para que la distancia de la ruta
        // coincida con la del entrenamiento.
        let isRide = workout.activity.isRide
        let loop = Self.demoLoop(length: isRide ? 12_000 : 2400)
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
                altitude: isRide ? 40 + 32 * sin(covered / 1500) : 12 + 8 * sin(covered / 380),
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
        return WorkoutDetailData(route: route, heartRate: heartRate, power: isRide ? demoPower(for: workout) : [], origin: .demo)
    }

    /// FC sintética cada 5 s (rodillo, sin ruta).
    private func demoHeartRate(for workout: WorkoutSummary) -> [HeartRatePoint] {
        var rng = generator(for: workout.start, salt: 0x4EA27)
        let average = workout.averageHeartRate ?? 135
        let maximum = workout.maxHeartRate ?? average + 15
        return stride(from: 0.0, through: workout.duration, by: 5).map { second in
            let warmup = min(second / 300, 1)
            let bpm = min(maximum, (average - 22) + 22 * warmup + 7 * sin(second / 300) + Double.random(in: -2...2, using: &rng))
            return HeartRatePoint(date: workout.start.addingTimeInterval(second), bpm: bpm.rounded())
        }
    }

    /// Potencia sintética, una lectura por segundo, solo si la salida tiene
    /// potencia media: terreno ondulado, bloques más fuertes en rodillo y algo
    /// de rueda libre (0 W) en exterior. Se escala para que la media coincida.
    private func demoPower(for workout: WorkoutSummary) -> [PowerSample] {
        guard workout.activity.isRide, let target = workout.averagePower, workout.duration > 0 else { return [] }
        var rng = generator(for: workout.start, salt: 0x9077E)
        let indoor = workout.activity == .indoorRide
        var raw: [Double] = []
        for second in 0..<Int(workout.duration) {
            let t = Double(second)
            var factor = indoor
                ? (second % 900 >= 600 ? 1.18 : 0.92)
                : 1 + 0.22 * sin(t / 420) + 0.08 * sin(t / 37)
            factor *= 1 + Double.random(in: -0.12...0.12, using: &rng)
            if !indoor && Double.random(in: 0..<1, using: &rng) < 0.05 { factor = 0 }
            raw.append(max(0, factor))
        }
        let mean = raw.reduce(0, +) / Double(max(raw.count, 1))
        guard mean > 0 else { return [] }
        return raw.enumerated().map { second, factor in
            let start = workout.start.addingTimeInterval(Double(second))
            return PowerSample(start: start, end: start.addingTimeInterval(1), watts: (factor / mean * target).rounded())
        }
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
        // La noche del viernes (diario demo: alcohol) se duerme algo peor.
        // y tras un día con mucha luz natural se duerme algo más.
        case .sleepDuration: return 7.4 + 0.7 * noise - (isSaturday(day) ? 0.4 : 0) + 0.006 * (value(.timeInDaylight, on: previousDay(day)) - 48)
        // Relaciones plausibles para la demo: dormir más se asocia a más HRV y menos
        // FC en reposo; un día de mucho ejercicio, a menos HRV al día siguiente.
        case .restingHeartRate: return (54 + 2 * slowTrend + 2 * noise - 1.5 * (value(.sleepDuration, on: day) - 7.4)).rounded()
        case .heartRateVariability:
            let sleepEffect = 9 * (value(.sleepDuration, on: day) - 7.4)
            let loadEffect = -0.08 * (value(.exerciseTime, on: previousDay(day)) - 36)
            return max(41, 62 + 6 * slowTrend + 6 * noise + sleepEffect + loadEffect - (isSaturday(day) ? 7 : 0)).rounded()
        case .heartRate: return (68 + 6 * noise).rounded()
        case .respiratoryRate: return 14.6 + 0.6 * noise
        case .vo2Max: return 47.8 + 0.6 * slowTrend + 0.2 * noise
        case .oxygenSaturation: return 0.97 + 0.01 * noise
        // Peso con una oscilación lenta (±0,8 kg en unos meses) y ruido diario realista.
        case .bodyMass: return ((74.5 + 0.8 * sin(Double(dayNumber(day)) / 45) + 0.3 * noise) * 10).rounded() / 10
        case .bodyFatPercentage: return ((0.182 + 0.006 * sin(Double(dayNumber(day)) / 45) + 0.004 * noise) * 1000).rounded() / 1000
        // Más luz el fin de semana; algo más de sueño tras días con mucha luz (patrón demo).
        case .timeInDaylight: return max(0, 48 + 30 * noise + (isWeekend(day) ? 25 : 0)).rounded()
        case .wristTemperature: return ((36.1 + 0.12 * noise) * 100).rounded() / 100
        case .leanBodyMass: return ((value(.bodyMass, on: day) * (1 - value(.bodyFatPercentage, on: day))) * 10).rounded() / 10
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

    private func makeRide(on day: Date, using rng: inout SeededRandomNumberGenerator) -> WorkoutSummary {
        let indoor = Double.random(in: 0..<1, using: &rng) < 0.3
        let speed = Double.random(in: indoor ? 27...32 : 23.5...31, using: &rng) / 3.6
        let duration = indoor ? Double.random(in: 2700...4500, using: &rng) : Double.random(in: 3600...10_800, using: &rng)
        let startHour = Double.random(in: 7...18, using: &rng)
        let average = Double.random(in: 126...148, using: &rng).rounded()
        let hasPower = indoor || Double.random(in: 0..<1, using: &rng) < 0.5
        let distance = speed * duration
        return WorkoutSummary(
            id: UUID(uuid: uuidBytes(for: day, salt: 0xB1)),
            activity: indoor ? .indoorRide : .outdoorRide,
            start: day.addingTimeInterval(startHour * 3600),
            duration: duration,
            distanceMeters: distance,
            averageHeartRate: average,
            maxHeartRate: average + Double.random(in: 14...28, using: &rng).rounded(),
            activeEnergyKilocalories: (duration / 3600 * 560).rounded(),
            averageCadence: hasPower ? Double.random(in: 80...92, using: &rng).rounded() : nil,
            origin: .demo,
            averagePower: hasPower ? Double.random(in: 165...215, using: &rng).rounded() : nil,
            elevationGain: indoor ? nil : (distance / 1000 * Double.random(in: 6...14, using: &rng)).rounded()
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

    private func isSaturday(_ day: Date) -> Bool {
        calendar.component(.weekday, from: day) == 7
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

    private func uuidBytes(for day: Date, salt: UInt64 = 0x1D) -> uuid_t {
        var rng = generator(for: day, salt: salt)
        let a = rng.next(), b = rng.next()
        func byte(_ v: UInt64, _ i: UInt64) -> UInt8 { UInt8((v >> (i * 8)) & 0xFF) }
        return (byte(a, 0), byte(a, 1), byte(a, 2), byte(a, 3), byte(a, 4), byte(a, 5), byte(a, 6), byte(a, 7),
                byte(b, 0), byte(b, 1), byte(b, 2), byte(b, 3), byte(b, 4), byte(b, 5), byte(b, 6), byte(b, 7))
    }
}
