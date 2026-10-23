import Foundation
import Testing
@testable import HalsynCore

/// Cliente simulado: devuelve datos sintéticos configurables y registra las
/// consultas, sin HealthKit.
final class MockHealthStoreClient: HealthStoreClient, @unchecked Sendable {
    var isHealthDataAvailable = true
    var needsAuthorization = true
    var authorizationRequests = 0
    var error: HealthStoreError?
    var statistics: [MetricKind: [DailyValue]] = [:]
    var recentSamples: [MetricKind: [MetricReading]] = [:]
    var sleep: [SleepSample] = []
    var workouts: [WorkoutSummary] = []
    private(set) var statisticsQueries: [(MetricKind, DailyAggregation, DateInterval)] = []

    func shouldRequestAuthorization() async throws -> Bool {
        if let error { throw error }
        return needsAuthorization
    }

    func requestAuthorization() async throws {
        authorizationRequests += 1
        needsAuthorization = false
    }

    func dailyStatistics(_ kind: MetricKind, aggregation: DailyAggregation, interval: DateInterval, calendar: Calendar) async throws -> [DailyValue] {
        if let error { throw error }
        statisticsQueries.append((kind, aggregation, interval))
        return (statistics[kind] ?? []).filter { interval.contains($0.day) && $0.day < interval.end }
    }

    func mostRecentSample(_ kind: MetricKind, in interval: DateInterval) async throws -> MetricReading? {
        if let error { throw error }
        return (recentSamples[kind] ?? [])
            .filter { $0.date >= interval.start && $0.date < interval.end }
            .max { $0.date < $1.date }
    }

    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
        if let error { throw error }
        return sleep.filter { $0.end > interval.start && $0.start < interval.end }
    }

    func runningWorkouts(limit: Int) async throws -> [WorkoutSummary] {
        if let error { throw error }
        return Array(workouts.prefix(limit))
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

/// "Hoy" es el 23 de octubre de 2026 a las 15:00 en Madrid.
private func makeProvider(_ client: MockHealthStoreClient) -> LiveHealthDataProvider {
    LiveHealthDataProvider(client: client, calendar: calendar, now: { date(23, 15) })
}

@Suite("Sueño")
struct SleepAggregatorTests {
    @Test func nightWindowRunsNoonToNoon() {
        let window = SleepAggregator.nightWindow(endingOn: date(23, 9), calendar: calendar)
        #expect(window.start == date(22, 12))
        #expect(window.end == date(23, 12))
    }

    @Test func onlyAsleepStagesCount() {
        let window = SleepAggregator.nightWindow(endingOn: date(23), calendar: calendar)
        let samples = [
            SleepSample(start: date(22, 23), end: date(23, 7), stage: .inBed),
            SleepSample(start: date(22, 23, 15), end: date(23, 1), stage: .asleepCore),
            SleepSample(start: date(23, 1), end: date(23, 1, 30), stage: .awake),
            SleepSample(start: date(23, 1, 30), end: date(23, 3), stage: .asleepDeep),
            SleepSample(start: date(23, 3), end: date(23, 6, 45), stage: .asleepREM),
        ]
        // 1 h 45 + 1 h 30 + 3 h 45 = 7 h
        #expect(SleepAggregator.asleepDuration(samples, in: window) == 7 * 3600)
    }

    @Test func overlappingSourcesAreNotDoubleCounted() {
        let window = SleepAggregator.nightWindow(endingOn: date(23), calendar: calendar)
        let samples = [
            SleepSample(start: date(22, 23), end: date(23, 6), stage: .asleepCore, sourceName: "Apple Watch"),
            SleepSample(start: date(23, 0), end: date(23, 7), stage: .asleepUnspecified, sourceName: "Otra app"),
        ]
        #expect(SleepAggregator.asleepDuration(samples, in: window) == 8 * 3600)
        // Empate a 7 h: gana la primera por orden alfabético, siempre la misma.
        #expect(SleepAggregator.dominantSource(samples, in: window) == "Apple Watch")
    }

    @Test func dominantSourceIsTheLongest() {
        let window = SleepAggregator.nightWindow(endingOn: date(23), calendar: calendar)
        let samples = [
            SleepSample(start: date(23, 1), end: date(23, 5), stage: .asleepCore, sourceName: "Apple Watch"),
            SleepSample(start: date(22, 23), end: date(23, 7), stage: .asleepCore, sourceName: "Zeta"),
        ]
        #expect(SleepAggregator.dominantSource(samples, in: window) == "Zeta")
    }

    @Test func samplesAreClippedToTheWindow() {
        let window = SleepAggregator.nightWindow(endingOn: date(23), calendar: calendar)
        let nap = SleepSample(start: date(23, 11), end: date(23, 13), stage: .asleepUnspecified)
        #expect(SleepAggregator.asleepDuration([nap], in: window) == 3600)
    }
}

@Suite("Proveedor HealthKit (mock)")
struct LiveHealthDataProviderTests {
    @Test func authorizationStates() async throws {
        let client = MockHealthStoreClient()
        let provider = makeProvider(client)
        #expect(await provider.authorizationState() == .notDetermined)
        try await provider.requestAuthorization()
        #expect(client.authorizationRequests == 1)
        #expect(await provider.authorizationState() == .requested)
        client.isHealthDataAvailable = false
        #expect(await provider.authorizationState() == .unavailable)
        await #expect(throws: HealthStoreError.unavailable) { try await provider.requestAuthorization() }
    }

    @Test func liveModeIsNotDemo() {
        #expect(makeProvider(MockHealthStoreClient()).mode == .live)
    }

    @Test func noSamplesMeansNoDataNotZero() async {
        let provider = makeProvider(MockHealthStoreClient())
        for kind in MetricKind.allCases {
            #expect(await provider.latest(kind, on: date(23)) == .noData, "\(kind)")
        }
    }

    @Test func errorsMapToDistinctStates() async {
        let client = MockHealthStoreClient()
        let provider = makeProvider(client)
        client.error = .databaseLocked
        #expect(await provider.latest(.steps, on: date(23)) == .temporarilyUnavailable)
        client.error = .failed("x")
        #expect(await provider.latest(.steps, on: date(23)) == .readFailed)
        client.error = .notAuthorized
        #expect(await provider.latest(.steps, on: date(23)) == .notAuthorized)
        client.error = nil
        client.isHealthDataAvailable = false
        #expect(await provider.latest(.steps, on: date(23)) == .unsupported)
    }

    @Test func dailyStatisticUsesTheDayAndAggregation() async throws {
        let client = MockHealthStoreClient()
        client.statistics[.steps] = [DailyValue(day: date(22), value: 9100), DailyValue(day: date(23), value: 4321)]
        let reading = try #require(await makeProvider(client).latest(.steps, on: date(23)).reading)
        #expect(reading.value == 4321)
        #expect(reading.origin == .healthKit(sourceName: nil))
        let query = try #require(client.statisticsQueries.first)
        #expect(query.1 == .sum)
        #expect(query.2 == DateInterval(start: date(23), end: date(24)))
    }

    @Test func latestMetricsLookBackAndKeepTheRealDate() async throws {
        let client = MockHealthStoreClient()
        let measured = MetricReading(kind: .vo2Max, value: 46.2, date: date(2, 18), origin: .healthKit(sourceName: "Apple Watch"))
        client.recentSamples[.vo2Max] = [measured]
        client.recentSamples[.restingHeartRate] = [MetricReading(kind: .restingHeartRate, value: 55, date: date(21, 8), origin: .healthKit(sourceName: nil))]
        let provider = makeProvider(client)
        #expect(await provider.latest(.vo2Max, on: date(23)).reading == measured)
        // La FC en reposo de hace dos días no se presenta como la de hoy.
        #expect(await provider.latest(.restingHeartRate, on: date(23)) == .noData)
    }

    @Test func sleepIsAggregatedPerNight() async throws {
        let client = MockHealthStoreClient()
        client.sleep = [
            SleepSample(start: date(22, 23), end: date(23, 6, 30), stage: .asleepCore, sourceName: "Apple Watch"),
            SleepSample(start: date(21, 23, 30), end: date(22, 6), stage: .asleepCore, sourceName: "Apple Watch"),
        ]
        let provider = makeProvider(client)
        let today = try #require(await provider.latest(.sleepDuration, on: date(23)).reading)
        #expect(today.value == 7.5)
        #expect(today.origin == .healthKit(sourceName: "Apple Watch"))
        let series = await provider.dailySeries(.sleepDuration, days: 3, endingOn: date(23))
        #expect(series.values.map(\.value) == [6.5, 7.5])
        #expect(series.values.map(\.day) == [date(22), date(23)])
    }

    @Test func seriesKeepGapsAndIgnoreTheFuture() async {
        let client = MockHealthStoreClient()
        client.statistics[.heartRateVariability] = [
            DailyValue(day: date(17), value: 60),
            DailyValue(day: date(20), value: 64),
            DailyValue(day: date(23), value: 58),
        ]
        let series = await makeProvider(client).dailySeries(.heartRateVariability, days: 7, endingOn: date(25))
        #expect(series.values.map(\.value) == [60, 64, 58], "sin ceros inventados en los días sin datos")
        #expect(series.values.last?.day == date(23))
    }

    @Test func noFutureDays() async {
        #expect(await makeProvider(MockHealthStoreClient()).latest(.steps, on: date(25)) == .noData)
    }

    @Test func scoresAndGoalsAreNotInvented() async {
        let provider = makeProvider(MockHealthStoreClient())
        #expect(await provider.dailyScore(on: date(23)) == nil)
        #expect(await provider.recoveryScore(on: date(23)) == nil)
        #expect(await provider.goals().isEmpty)
    }

    @Test func workoutsPassThroughAndFailSoft() async {
        let client = MockHealthStoreClient()
        let run = WorkoutSummary(activity: .outdoorRun, start: date(22, 7), duration: 1800, distanceMeters: 6000, averageHeartRate: 150, maxHeartRate: 171, activeEnergyKilocalories: 400, averageCadence: nil, origin: .healthKit(sourceName: "Apple Watch"))
        client.workouts = [run]
        let provider = makeProvider(client)
        #expect(await provider.recentWorkouts(limit: 5) == [run])
        client.error = .databaseLocked
        #expect(await provider.recentWorkouts(limit: 5).isEmpty)
    }
}
