import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
}

@Suite("VILA · noches de sueño")
struct SleepNightTests {
    @Test func stagesTimesAndEfficiency() throws {
        let samples = [
            SleepSample(start: date(9, 23, 0), end: date(10, 1, 0), stage: .asleepCore, sourceName: "Watch"),
            SleepSample(start: date(10, 1, 0), end: date(10, 1, 20), stage: .awake, sourceName: "Watch"),
            SleepSample(start: date(10, 1, 20), end: date(10, 2, 20), stage: .asleepDeep, sourceName: "Watch"),
            SleepSample(start: date(10, 2, 20), end: date(10, 7, 0), stage: .asleepREM, sourceName: "Watch"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: date(10, 0), calendar: calendar, origin: .demo))
        #expect(night.asleep == (2 * 60 + 60 + 280) * 60)
        #expect(night.sleepStart == date(9, 23))
        #expect(night.sleepEnd == date(10, 7))
        #expect(night.awake == 20 * 60)
        #expect(night.stages[.asleepDeep] == 3600)
        #expect(night.hasStages)
        #expect(abs((night.efficiency ?? 0) - 460.0 / 480.0) < 0.0001)
    }

    @Test func stagesComeOnlyFromTheDominantSource() throws {
        let samples = [
            SleepSample(start: date(9, 23), end: date(10, 7), stage: .asleepCore, sourceName: "Watch"),
            SleepSample(start: date(9, 23), end: date(10, 6), stage: .asleepDeep, sourceName: "OtraApp"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: date(10, 0), calendar: calendar, origin: .demo))
        #expect(night.sourceName == "Watch")
        #expect(night.stages[.asleepDeep] == nil)
        // El total sí fusiona fuentes sin contar dos veces.
        #expect(night.asleep == 8 * 3600)
    }

    @Test func unspecifiedSleepHasNoStages() throws {
        let samples = [SleepSample(start: date(9, 23), end: date(10, 6), stage: .asleepUnspecified, sourceName: "iPhone")]
        let night = try #require(SleepAnalysis.night(samples, endingOn: date(10, 0), calendar: calendar, origin: .demo))
        #expect(!night.hasStages)
    }

    @Test func noSleepNoNight() {
        let samples = [SleepSample(start: date(9, 22), end: date(10, 7), stage: .inBed, sourceName: "iPhone")]
        #expect(SleepAnalysis.night(samples, endingOn: date(10, 0), calendar: calendar, origin: .demo) == nil)
    }

    @Test func regularityHandlesMidnight() throws {
        // Dormirse a las 23:30 y a la 00:30 alterna: media 00:00, variación ~30 min.
        let nights = (10...15).map { day -> SleepNight in
            let late = day % 2 == 0
            let start = late ? date(day, 0, 30) : date(day - 1, 23, 30)
            return SleepNight(day: date(day, 0), asleep: 7 * 3600, sleepStart: start, sleepEnd: date(day, 7), awake: 0, stages: [:], sourceName: nil, origin: .demo)
        }
        let regularity = try #require(SleepRegularity(nights, calendar: calendar))
        let average = SleepRegularity.clockTime(minutesFromNoon: regularity.averageSleepStart)
        #expect(average.hour == 0 && average.minute == 0)
        #expect(abs(regularity.sleepStartVariation - 32.86) < 0.1)
        #expect(regularity.sleepEndVariation == 0)
    }

    @Test func regularityNeedsFiveNights() {
        let night = SleepNight(day: date(10, 0), asleep: 7 * 3600, sleepStart: date(9, 23), sleepEnd: date(10, 6), awake: 0, stages: [:], sourceName: nil, origin: .demo)
        #expect(SleepRegularity(Array(repeating: night, count: 4), calendar: calendar) == nil)
    }

    @Test func shortfallOnlyCountsNightsBelowTarget() {
        let nights = [6.0, 8.5, 7.0].map { hours in
            SleepNight(day: date(10, 0), asleep: hours * 3600, sleepStart: date(9, 23), sleepEnd: date(10, 7), awake: 0, stages: [:], sourceName: nil, origin: .demo)
        }
        #expect(SleepTarget.shortfall(nights, targetHours: 8) == 3 * 3600)
    }

    @Test func demoNightsMatchTheDemoSeries() async {
        let now = date(20, 10)
        let provider = DemoHealthDataProvider(calendar: calendar, now: { now })
        let nights = await provider.sleepNights(endingOn: now, days: 7)
        let series = await provider.dailySeries(.sleepDuration, days: 7, endingOn: now)
        #expect(nights.count == 7)
        for (night, value) in zip(nights, series.values) {
            #expect(abs(night.asleep / 3600 - value.value) < 0.01)
            #expect(night.hasStages)
            #expect(night.origin == .demo)
        }
        #expect(await provider.sleepNights(endingOn: now, days: 7) == nights)
    }
}

@Suite("VILA · RecoveryEngine")
struct RecoveryEngineTests {
    private let day = date(20, 0)

    /// Historial con 28 días de base estable y el valor de hoy indicado.
    private func history(hrv: Double? = 60, rhr: Double? = 55, sleep: Double? = 8, recentExercise: Double = 30, baselineDays: Int = 28, includeYesterdayOnly: Bool = false) -> DailyHistory {
        func series(_ kind: MetricKind, base: Double, jitter: Double, today: Double?) -> MetricSeries {
            var values: [DailyValue] = (1...baselineDays).map { offset in
                let value = base + (offset % 2 == 0 ? jitter : -jitter)
                return DailyValue(day: calendar.date(byAdding: .day, value: -offset, to: day)!, value: value)
            }
            if let today {
                let target = includeYesterdayOnly ? calendar.date(byAdding: .day, value: -1, to: day)! : day
                values.removeAll { calendar.isDate($0.day, inSameDayAs: target) }
                values.append(DailyValue(day: target, value: today))
            }
            return MetricSeries(kind: kind, values: values, origin: .demo)
        }
        var exercise = (1...28).map { DailyValue(day: calendar.date(byAdding: .day, value: -$0, to: day)!, value: 30) }
        for offset in 1...3 {
            exercise[offset - 1] = DailyValue(day: calendar.date(byAdding: .day, value: -offset, to: day)!, value: recentExercise)
        }
        return DailyHistory(series: [
            series(.heartRateVariability, base: 60, jitter: 5, today: hrv),
            series(.restingHeartRate, base: 55, jitter: 2, today: rhr),
            MetricSeries(kind: .sleepDuration, values: sleep.map { [DailyValue(day: day, value: $0)] } ?? [], origin: .demo),
            MetricSeries(kind: .exerciseTime, values: exercise, origin: .demo),
        ], calendar: calendar)
    }

    private let engine = RecoveryEngine()

    @Test func atBaselineIsAroundSeventyFive() {
        let estimate = engine.evaluate(day: day, history: history(), origin: .demo)
        // HRV y FC reposo en la media (75), sueño 100, carga habitual 100.
        // 75 × 0,35 + 75 × 0,25 + 100 × 0,25 + 100 × 0,15 = 85
        #expect(estimate.value == 85)
        #expect(estimate.confidence == .high)
        #expect(estimate.coverage == 1)
    }

    @Test func lowHRVAndHighRestingHeartRateLowerRecovery() {
        let good = engine.evaluate(day: day, history: history(), origin: .demo).value ?? 0
        let bad = engine.evaluate(day: day, history: history(hrv: 42, rhr: 61), origin: .demo)
        #expect((bad.value ?? 100) < good - 20)
        #expect(bad.components.first { $0.kind == .heartRateVariability }?.impact == .negative)
        #expect(bad.components.first { $0.kind == .restingHeartRate }?.impact == .negative)
    }

    @Test func hardRecentDaysLowerRecovery() {
        let estimate = engine.evaluate(day: day, history: history(recentExercise: 90), origin: .demo)
        let load = estimate.components.first { $0.kind == .recentLoad }
        #expect(load?.impact == .negative)
        #expect((load?.score ?? 100) < 70)
    }

    @Test func needsAPhysiologicalSignal() {
        // Solo sueño y ejercicio: sin HRV ni FC en reposo no hay estimación.
        let exercise = (1...28).map { DailyValue(day: calendar.date(byAdding: .day, value: -$0, to: day)!, value: 30) }
        let onlyBehaviour = DailyHistory(series: [
            MetricSeries(kind: .sleepDuration, values: [DailyValue(day: day, value: 8)], origin: .demo),
            MetricSeries(kind: .exerciseTime, values: exercise, origin: .demo),
        ], calendar: calendar)
        let estimate = engine.evaluate(day: day, history: onlyBehaviour, origin: .demo)
        #expect(estimate.value == nil)
        #expect(estimate.dailyScore == nil)
    }

    @Test func insufficientBaselineIsReported() {
        let estimate = engine.evaluate(day: day, history: history(baselineDays: 4), origin: .demo)
        #expect(estimate.components.first { $0.kind == .heartRateVariability }?.missingReason == .insufficientHistory)
        #expect(estimate.value == nil)
    }

    @Test func fallsBackToYesterdayAndSaysSo() {
        let estimate = engine.evaluate(day: day, history: history(includeYesterdayOnly: true), origin: .demo)
        let hrv = estimate.components.first { $0.kind == .heartRateVariability }
        #expect(hrv?.usesPreviousDay == true)
        #expect(estimate.value != nil)
        #expect(estimate.confidence != .high)
    }

    @Test func curves() {
        #expect(RecoveryEngine.baselineScore(z: 0) == 75)
        #expect(RecoveryEngine.baselineScore(z: 2) == 100)
        #expect(RecoveryEngine.baselineScore(z: 5) == 100)
        #expect(RecoveryEngine.baselineScore(z: -3) == 15)
        #expect(RecoveryEngine.recentLoadScore(ratio: 0.5) == 100)
        #expect(RecoveryEngine.recentLoadScore(ratio: 1.75) == 70)
        #expect(RecoveryEngine.recentLoadScore(ratio: 3) == 40)
    }

    @Test func demoRecoveryComesFromTheEngine() async {
        let now = date(20, 10)
        let provider = DemoHealthDataProvider(calendar: calendar, now: { now })
        let estimates = await provider.recoveryEstimates(endingOn: now, days: 14)
        #expect(estimates.count == 14)
        #expect(estimates.allSatisfy { $0.origin == .demo && $0.engineVersion == RecoveryEngine.version })
        let score = await provider.recoveryScore(on: now)
        #expect(score?.value == estimates.last?.value)
    }
}

@Suite("VILA · hipnograma")
struct HypnogramTests {
    @Test func segmentsAreOrderedAndClipped() throws {
        let samples = [
            SleepSample(start: date(10, 1), end: date(10, 3), stage: .asleepDeep, sourceName: "W"),
            SleepSample(start: date(9, 22), end: date(10, 8), stage: .inBed, sourceName: "W"),
            SleepSample(start: date(9, 23), end: date(10, 1), stage: .asleepCore, sourceName: "W"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: date(10, 0), calendar: calendar, origin: .demo))
        #expect(night.segments.map(\.stage) == [.asleepCore, .asleepDeep])
        #expect(night.segments.first?.start == date(9, 23))
    }

    @Test func noSegmentsWithoutStages() throws {
        let samples = [SleepSample(start: date(9, 23), end: date(10, 6), stage: .asleepUnspecified, sourceName: "iPhone")]
        let night = try #require(SleepAnalysis.night(samples, endingOn: date(10, 0), calendar: calendar, origin: .demo))
        #expect(night.segments.isEmpty)
    }
}
