import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Día de referencia de los tests: 30 de octubre de 2026.
private let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30))!

private func dayOffset(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: day)!
}

/// Construye un historial: `values(offset)` da el valor del día `day + offset`
/// para offsets en `range` (nil = sin dato).
private func series(_ kind: MetricKind, _ range: ClosedRange<Int>, _ values: (Int) -> Double?) -> MetricSeries {
    MetricSeries(kind: kind, values: range.compactMap { offset in values(offset).map { DailyValue(day: dayOffset(offset), value: $0) } }, origin: .demo)
}

/// Historial "sano y estable" de 35 días con todas las dimensiones.
private func stableHistory(
    sleepToday: Double = 7.5,
    restingToday: Double = 55,
    hrvToday: Double = 60,
    steps: Double = 9000,
    exercisePerDay: Double = 30
) -> DailyHistory {
    DailyHistory(series: [
        series(.sleepDuration, -34...0) { $0 == 0 ? sleepToday : 7.4 },
        series(.restingHeartRate, -34...0) { $0 == 0 ? restingToday : (54 + Double(abs($0) % 3)) },
        series(.heartRateVariability, -34...0) { $0 == 0 ? hrvToday : (58 + Double(abs($0) % 5)) },
        series(.steps, -34...0) { _ in steps },
        series(.exerciseTime, -34...0) { _ in exercisePerDay },
    ], calendar: calendar)
}

@Suite("HealthScoreEngine · curvas")
struct HealthScoreCurveTests {
    @Test func sleepCurve() {
        let range = 7.0...9.0
        #expect(HealthScoreEngine.sleepScore(hours: 7, recommended: range) == 100)
        #expect(HealthScoreEngine.sleepScore(hours: 9, recommended: range) == 100)
        #expect(abs(HealthScoreEngine.sleepScore(hours: 6, recommended: range) - 66.67) < 0.01)
        #expect(HealthScoreEngine.sleepScore(hours: 4, recommended: range) == 0)
        #expect(HealthScoreEngine.sleepScore(hours: 2, recommended: range) == 0)
        // Dormir de más baja poco y nunca por debajo de 70.
        #expect(HealthScoreEngine.sleepScore(hours: 10, recommended: range) == 85)
        #expect(HealthScoreEngine.sleepScore(hours: 14, recommended: range) == 70)
    }

    @Test func deviationCurveOnlyPenalisesUnfavourableSide() {
        #expect(HealthScoreEngine.unfavourableDeviationScore(z: -3) == 100, "estar 'mejor' que tu media no suma más")
        #expect(HealthScoreEngine.unfavourableDeviationScore(z: 1) == 100)
        #expect(HealthScoreEngine.unfavourableDeviationScore(z: 2) == 70)
        #expect(HealthScoreEngine.unfavourableDeviationScore(z: 5) == 40)
    }

    @Test func loadBalanceCurve() {
        #expect(HealthScoreEngine.loadBalanceScore(ratio: 1.0) == 100)
        #expect(HealthScoreEngine.loadBalanceScore(ratio: 1.3) == 100)
        #expect(abs(HealthScoreEngine.loadBalanceScore(ratio: 1.65) - 70) < 0.01)
        #expect(HealthScoreEngine.loadBalanceScore(ratio: 3) == 40)
        #expect(HealthScoreEngine.loadBalanceScore(ratio: 0.55) == 85)
        #expect(HealthScoreEngine.loadBalanceScore(ratio: 0) == 70, "descansar no se castiga como la sobrecarga")
    }

    @Test func weightsValidation() {
        #expect(HealthScoreWeights.provisional.isValid)
        #expect(abs(HealthScoreWeights.provisional.total - 1) < 1e-9)
        #expect(!HealthScoreWeights(sleep: -1).isValid)
        #expect(!HealthScoreWeights(sleep: 0, cardiovascular: 0, movement: 0, exercise: 0, balance: 0).isValid)
    }
}

@Suite("HealthScoreEngine · evaluación")
struct HealthScoreEngineTests {
    let engine = HealthScoreEngine()

    @Test func stableHealthyDayScoresHigh() throws {
        let result = engine.evaluate(day: day, history: stableHistory())
        let score = try #require(result.score)
        #expect(score >= 95)
        #expect(result.breakdown.coverage == 1)
        #expect(result.breakdown.confidence == .high)
        #expect(result.breakdown.dimensions.allSatisfy { $0.score != nil })
        #expect(result.breakdown.engineVersion == HealthScoreEngine.version)
    }

    @Test func shortSleepAndElevatedRestingHRLowerTheScore() throws {
        let good = try #require(engine.evaluate(day: day, history: stableHistory()).score)
        let result = engine.evaluate(day: day, history: stableHistory(sleepToday: 5, restingToday: 65))
        let bad = try #require(result.score)
        #expect(bad < good - 15)
        // Los factores desfavorables van primero.
        #expect(result.breakdown.factors.first?.impact == .negative)
        #expect(result.breakdown.factors.contains { $0.kind == .sleepDuration(hours: 5) && $0.impact == .negative })
    }

    @Test func lowerRestingHRIsNotRewardedBeyondBaseline() {
        let usual = engine.evaluate(day: day, history: stableHistory(restingToday: 55))
        let lower = engine.evaluate(day: day, history: stableHistory(restingToday: 45))
        #expect(usual.breakdown.dimensions.first { $0.dimension == .cardiovascular }?.score == 100)
        #expect(lower.breakdown.dimensions.first { $0.dimension == .cardiovascular }?.score == 100)
    }

    @Test func todayIsNotPenalisedForAPartialDay() {
        // Hoy solo hay 1.200 pasos y 0 min de ejercicio (son las 9:00).
        let history = DailyHistory(series: [
            series(.steps, -34...0) { $0 == 0 ? 1200 : 9000 },
            series(.exerciseTime, -34...0) { $0 == 0 ? 0 : 30 },
            series(.sleepDuration, -34...0) { _ in 7.5 },
        ], calendar: calendar)
        let dims = engine.evaluate(day: day, history: history).breakdown.dimensions
        #expect(dims.first { $0.dimension == .movement }?.score == 100)
        #expect(dims.first { $0.dimension == .exercise }?.score == 100)
    }

    @Test func aRestDayDoesNotPenaliseExercise() {
        // 5 días de 40 min y 2 de descanso: 200 min/semana.
        let history = DailyHistory(series: [
            series(.exerciseTime, -34...0) { [-3, -6].contains($0) ? 0 : 40 },
        ], calendar: calendar)
        #expect(engine.evaluate(day: day, history: history).breakdown.dimensions.first { $0.dimension == .exercise }?.score == 100)
    }

    @Test func stepsAreCappedAtTheReference() {
        let normal = engine.evaluate(day: day, history: stableHistory(steps: 8000))
        let lots = engine.evaluate(day: day, history: stableHistory(steps: 25000))
        #expect(normal.breakdown.dimensions.first { $0.dimension == .movement }?.score == 100)
        #expect(lots.breakdown.dimensions.first { $0.dimension == .movement }?.score == 100)
        let few = engine.evaluate(day: day, history: stableHistory(steps: 4000))
        #expect(few.breakdown.dimensions.first { $0.dimension == .movement }?.score == 50)
    }

    @Test func loadSpikeAffectsBalance() throws {
        // 20 min/día durante 3 semanas y 60 min/día la última semana.
        let history = DailyHistory(series: [
            series(.exerciseTime, -34...0) { $0 >= -7 ? 60 : 20 },
        ], calendar: calendar)
        let balance = try #require(engine.evaluate(day: day, history: history).breakdown.dimensions.first { $0.dimension == .balance })
        #expect((balance.score ?? 100) < 100)
    }

    @Test func noScoreWithoutEnoughCoverage() {
        // Solo sueño (25 %): por debajo del 60 % mínimo.
        let history = DailyHistory(series: [series(.sleepDuration, -3...0) { _ in 7.5 }], calendar: calendar)
        let result = engine.evaluate(day: day, history: history)
        #expect(result.score == nil)
        #expect(result.breakdown.coverage == 0.25)
        #expect(result.breakdown.confidence == .low)
    }

    @Test func cardiovascularNeedsABaseline() {
        let history = DailyHistory(series: [
            series(.restingHeartRate, -3...0) { _ in 55 },
            series(.heartRateVariability, -3...0) { _ in 60 },
        ], calendar: calendar)
        let cardio = engine.evaluate(day: day, history: history).breakdown.dimensions.first { $0.dimension == .cardiovascular }
        #expect(cardio?.score == nil)
        #expect(cardio?.missingReason == .insufficientHistory)
    }

    @Test func missingDimensionsAreRenormalisedNotZeroed() throws {
        // Sin HRV ni FC: el resto (75 % del peso) se reparte, no cuenta como 0.
        let history = DailyHistory(series: [
            series(.sleepDuration, -34...0) { _ in 8 },
            series(.steps, -34...0) { _ in 9000 },
            series(.exerciseTime, -34...0) { _ in 30 },
        ], calendar: calendar)
        let result = engine.evaluate(day: day, history: history)
        #expect(try #require(result.score) == 100)
        #expect(result.breakdown.coverage == 0.75)
        #expect(result.breakdown.confidence == .medium)
    }

    @Test func weightsAreConfigurable() throws {
        let sleepOnly = HealthScoreEngine(configuration: HealthScoreConfiguration(
            weights: HealthScoreWeights(sleep: 1, cardiovascular: 0, movement: 0, exercise: 0, balance: 0)
        ))
        let result = sleepOnly.evaluate(day: day, history: stableHistory(sleepToday: 6))
        #expect(try #require(result.score) == 67)
    }

    @Test func deterministic() {
        #expect(engine.evaluate(day: day, history: stableHistory()) == engine.evaluate(day: day, history: stableHistory()))
    }
}

@Suite("Puntuaciones desde proveedores")
struct ScoreComputationTests {
    private let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 21))!

    @Test func demoScoreComesFromTheEngineAndIsLabelledDemo() async throws {
        let demo = DemoHealthDataProvider(seed: 3, calendar: calendar, now: { now })
        let score = try #require(await demo.dailyScore(on: now))
        #expect(score.origin == .demo)
        #expect(score.breakdown?.engineVersion == HealthScoreEngine.version)
        #expect(score.weeklyChange != nil)
    }

    @Test func historyHasOneScorePerDayInOrder() async {
        let demo = DemoHealthDataProvider(seed: 3, calendar: calendar, now: { now })
        let scores = await demo.dailyScores(endingOn: now, days: 14)
        #expect(scores.count == 14)
        #expect(zip(scores, scores.dropFirst()).allSatisfy { $0.day < $1.day })
        #expect(scores.last.map { calendar.isDate($0.day, inSameDayAs: now) } == true)
    }

    @Test func liveScoreIsDerivedAndAbsentWithoutData() async throws {
        let client = MockHealthStoreClient()
        let provider = LiveHealthDataProvider(client: client, calendar: calendar, now: { now })
        #expect(await provider.dailyScore(on: now) == nil)
        for (kind, value) in [(MetricKind.steps, 9000.0), (.exerciseTime, 30), (.restingHeartRate, 55), (.heartRateVariability, 60)] {
            client.statistics[kind] = (-40...0).map { DailyValue(day: calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))!, value: value) }
        }
        let score = try #require(await provider.dailyScore(on: now))
        #expect(score.origin == .derived(engine: "HealthScoreEngine"))
        #expect(score.value == 100)
    }
}

@Suite("Resumen del día")
struct DailySummaryTests {
    let composer = DailySummaryComposer()

    @Test func statementsUseOnlyAvailableData() {
        let history = DailyHistory(series: [series(.sleepDuration, 0...0) { _ in 6.2 }], calendar: calendar)
        #expect(composer.compose(day: day, history: history, score: nil) == [.sleep(hours: 6.2, withinRecommendation: false)])
    }

    @Test func activityAndRestingHRRelations() {
        let history = DailyHistory(series: [
            series(.steps, -28...0) { $0 == 0 ? 12000 : 8000 },
            series(.restingHeartRate, -28...0) { $0 == 0 ? 55 : 55 },
        ], calendar: calendar)
        let statements = composer.compose(day: day, history: history, score: nil)
        #expect(statements.contains(.activity(.above)))
        #expect(statements.contains(.restingHeartRate(.within)))
    }

    @Test func overallComesFirstWhenThereIsAScore() {
        let score = DailyScore(day: day, value: 82, weeklyChange: nil, origin: .demo)
        let statements = composer.compose(day: day, history: stableHistory(), score: score)
        #expect(statements.first == .overall(.good))
        #expect(statements.contains(.weeklyExercise(minutes: 210, meetsReference: true)))
    }
}
