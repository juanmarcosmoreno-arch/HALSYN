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

    public func dailyScore(on day: Date) async -> DailyScore? {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: now()) else { return nil }
        let today = demoScoreValue(on: start)
        let previousWeek = (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.map(demoScoreValue(on:))
        let average = Double(previousWeek.reduce(0, +)) / Double(previousWeek.count)
        return DailyScore(day: start, value: today, weeklyChange: Int((Double(today) - average).rounded()), origin: .demo)
    }

    public func recoveryScore(on day: Date) async -> DailyScore? {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: now()) else { return nil }
        var rng = generator(for: start, salt: 0x7EC0)
        let value = Int((72 + 10 * sin(Double(dayNumber(start)) / 4) + 8 * Double.random(in: -1...1, using: &rng)).rounded())
        return DailyScore(day: start, value: value, weeklyChange: nil, origin: .demo)
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
        case .steps: return (8600 + 2600 * noise).rounded()
        case .walkingRunningDistance: return 6400 + 2200 * noise
        case .activeEnergy: return 540 + 160 * noise
        case .exerciseTime: return max(0, 36 + 22 * noise).rounded()
        case .sleepDuration: return 7.4 + 0.7 * noise
        case .restingHeartRate: return (54 + 2 * slowTrend + 2 * noise).rounded()
        case .heartRateVariability: return (62 + 6 * slowTrend + 9 * noise).rounded()
        case .heartRate: return (68 + 6 * noise).rounded()
        case .respiratoryRate: return 14.6 + 0.6 * noise
        case .vo2Max: return 47.8 + 0.6 * slowTrend + 0.2 * noise
        case .oxygenSaturation: return 0.97 + 0.01 * noise
        }
    }

    private func demoScoreValue(on day: Date) -> Int {
        var rng = generator(for: day, salt: 0x5C0E)
        return Int((76 + 8 * sin(Double(dayNumber(day)) / 5) + 6 * Double.random(in: -1...1, using: &rng)).rounded())
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
