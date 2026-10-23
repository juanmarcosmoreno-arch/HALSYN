import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar
}()

private let end = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!

private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: -offset, to: end)!
}

@Suite("INSIKT · estadística")
struct StatsTests {
    @Test func studentTMatchesTables() throws {
        // t = 2,228 con 10 gl → p bilateral 0,05 (tabla t de Student).
        let p = try #require(Stats.studentTTwoSidedP(t: 2.228, df: 10))
        #expect(abs(p - 0.05) < 0.001)
        // t = 2,0 con 10 gl → p ≈ 0,0734.
        let q = try #require(Stats.studentTTwoSidedP(t: 2.0, df: 10))
        #expect(abs(q - 0.0734) < 0.0005)
        #expect(try #require(Stats.studentTTwoSidedP(t: 0, df: 5)) == 1)
    }

    @Test func incompleteBetaKnownValues() {
        // I_x(1, 1) = x; I_0,5(a, a) = 0,5.
        #expect(abs(Stats.regularizedIncompleteBeta(x: 0.3, a: 1, b: 1) - 0.3) < 1e-10)
        #expect(abs(Stats.regularizedIncompleteBeta(x: 0.5, a: 4, b: 4) - 0.5) < 1e-10)
    }

    @Test func anovaMatchesHandComputation() throws {
        // Medias 3, 4 y 8 (gran media 5): entre = 70, dentro = 30 → F = (70/2)/(30/12) = 14.
        let result = try #require(Stats.oneWayANOVA([[1, 2, 3, 4, 5], [2, 3, 4, 5, 6], [6, 7, 8, 9, 10]]))
        #expect(abs(result.f - 14) < 1e-9)
        #expect(result.pValue < 0.001)
    }

    @Test func fDistributionMatchesTable() {
        // F crítico (2, 12) al 5 % = 3,885: p = I_{d2/(d2+d1·F)}(d2/2, d1/2).
        let p = Stats.regularizedIncompleteBeta(x: 12 / (12 + 2 * 3.885), a: 6, b: 1)
        #expect(abs(p - 0.05) < 0.001)
    }

    @Test func ranksAverageTies() {
        #expect(Stats.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
    }

    @Test func spearmanIsOneForMonotone() throws {
        let x = (1...20).map(Double.init)
        let y = x.map { $0 * $0 }
        #expect(abs(try #require(Stats.spearman(x, y)) - 1) < 1e-12)
        #expect(abs(try #require(Stats.spearman(x, y.reversed())) + 1) < 1e-12)
    }

    @Test func correlationPValue() throws {
        // r = 0,444 con n = 20 → p ≈ 0,05 (tabla de valores críticos de r).
        let p = try #require(Stats.correlationPValue(0.444, n: 20))
        #expect(abs(p - 0.05) < 0.002)
    }

    @Test func welchDetectsShift() throws {
        let a = [10.0, 11, 9, 10, 12, 8, 10, 11, 9, 10]
        let b = a.map { $0 + 3 }
        let result = try #require(Stats.welch(a, b))
        #expect(result.difference == 3)
        #expect(result.pValue < 0.001)
        #expect(result.effectSize > 2)
    }

    @Test func benjaminiHochbergKnownExample() {
        let q = Stats.benjaminiHochberg([0.01, 0.04, 0.03, 0.005])
        // Ordenados: 0,005·4/1 = 0,02; 0,01·4/2 = 0,02; 0,03·4/3 = 0,04; 0,04·4/4 = 0,04.
        #expect(q.map { ($0 * 1000).rounded() / 1000 } == [0.02, 0.04, 0.04, 0.02])
    }
}

@Suite("INSIKT · motor")
struct InsightEngineTests {
    private let engine = InsightEngine()

    private func series(_ kind: MetricKind, days: Int, _ value: (Int) -> Double?) -> MetricSeries {
        MetricSeries(kind: kind, values: (0..<days).compactMap { offset in value(offset).map { DailyValue(day: day(offset), value: $0) } }, origin: .demo)
    }

    private func noise(_ offset: Int, seed: UInt64 = 7) -> Double {
        var rng = SeededRandomNumberGenerator(seed: seed &+ UInt64(offset) &* 2654435761)
        return Double.random(in: -1...1, using: &rng)
    }

    @Test func detectsRealTrendAndItsDirection() throws {
        // FC en reposo: 58 lpm hace 4–8 semanas, 54 lpm en las últimas 4.
        let rhr = series(.restingHeartRate, days: 56) { offset in (offset < 28 ? 54 : 58) + 1.5 * noise(offset) }
        let report = engine.analyze(history: DailyHistory(series: [rhr], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        let trend = try #require(report.trends.first { $0.metric == .restingHeartRate })
        #expect(abs(trend.difference + 4) < 1)
        #expect(trend.isFavorable == true)
        #expect(trend.qValue < 0.05)
    }

    @Test func ignoresNoise() {
        let rhr = series(.restingHeartRate, days: 56) { 55 + 2 * noise($0) }
        let report = engine.analyze(history: DailyHistory(series: [rhr], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        #expect(report.trends.isEmpty)
    }

    @Test func trendNeedsEnoughDaysAndSaysHowMany() {
        let rhr = series(.restingHeartRate, days: 56) { offset in offset % 3 == 0 ? 55 : nil }
        let report = engine.analyze(history: DailyHistory(series: [rhr], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        #expect(report.trends.isEmpty)
        let requirement = report.requirements.first { $0.analysis == .trends && $0.metric == .restingHeartRate }
        #expect(requirement?.need == 14)
        #expect((requirement?.have ?? 99) < 14)
    }

    @Test func findsCuratedRelationship() throws {
        // HRV del día depende del sueño de esa noche.
        let sleep = series(.sleepDuration, days: 90) { 7.2 + 0.8 * noise($0, seed: 3) }
        let sleepByDay = Dictionary(uniqueKeysWithValues: sleep.values.map { ($0.day, $0.value) })
        let hrv = series(.heartRateVariability, days: 90) { offset in 40 + 6 * (sleepByDay[day(offset)] ?? 7.2) + 2 * noise(offset, seed: 11) }
        let report = engine.analyze(history: DailyHistory(series: [sleep, hrv], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        let relation = try #require(report.relationships.first { $0.candidate.predictor == .sleepDuration && $0.candidate.outcome == .heartRateVariability })
        #expect(relation.rho > 0.5)
        #expect(relation.highGroupMean > relation.lowGroupMean)
        #expect(relation.qValue < 0.05)
    }

    @Test func noRelationshipFromIndependentData() {
        let sleep = series(.sleepDuration, days: 90) { 7.2 + 0.8 * noise($0, seed: 3) }
        let hrv = series(.heartRateVariability, days: 90) { 60 + 8 * noise($0, seed: 99) }
        let report = engine.analyze(history: DailyHistory(series: [sleep, hrv], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        #expect(report.relationships.isEmpty)
    }

    @Test func relationshipRequirementWithFewPairs() {
        let sleep = series(.sleepDuration, days: 10) { _ in 7 }
        let report = engine.analyze(history: DailyHistory(series: [sleep], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        #expect(report.requirements.contains { $0.analysis == .relationships && $0.need == 21 })
    }

    @Test func weekdayPattern() throws {
        let steps = series(.steps, days: 84) { offset in
            let weekday = calendar.component(.weekday, from: day(offset))
            return (weekday == 1 || weekday == 7 ? 12000 : 7000) + 800 * noise(offset)
        }
        let report = engine.analyze(history: DailyHistory(series: [steps], calendar: calendar), endingOn: end, workouts: [], origin: .demo)
        let pattern = try #require(report.weekdays.first { $0.metric == .steps })
        #expect([1, 7].contains(pattern.highest))
        #expect(![1, 7].contains(pattern.lowest))
    }

    @Test func recordsUseRealDatesAndSensibleRules() throws {
        let steps = series(.steps, days: 30) { $0 == 12 ? 21000 : 8000 }
        let short = WorkoutSummary(activity: .outdoorRun, start: day(3), duration: 600, distanceMeters: 2500, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        let long = WorkoutSummary(activity: .outdoorRun, start: day(9), duration: 3600, distanceMeters: 12000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        let report = engine.analyze(history: DailyHistory(series: [steps], calendar: calendar), endingOn: end, workouts: [short, long], origin: .demo)
        let mostSteps = try #require(report.records.first { $0.kind == .mostSteps })
        #expect(mostSteps.value == 21000 && mostSteps.date == day(12))
        #expect(report.records.first { $0.kind == .longestRun }?.value == 12000)
        // La carrera de 2,5 km es más rápida, pero no cuenta para el récord de ritmo (< 3 km).
        #expect(report.records.first { $0.kind == .fastestRun }?.date == day(9))
    }

    @Test func demoShowsLabelledPatterns() async {
        let provider = DemoHealthDataProvider(calendar: calendar, now: { end })
        let report = await provider.computeInsights(endingOn: end, calendar: calendar, origin: .demo)
        #expect(report.origin == .demo)
        #expect(report.relationships.contains { $0.candidate.predictor == .sleepDuration && $0.candidate.outcome == .heartRateVariability })
        #expect(report.weekdays.contains { $0.metric == .steps })
        #expect(!report.records.isEmpty)
    }
}
