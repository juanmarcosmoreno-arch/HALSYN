import Foundation
import Testing
@testable import HalsynCore

@Suite("Evolución · Fase 2: adaptación individual y predicción")
struct EvolutionPhase2Tests {
    private let calendar = NovemberFixture.calendar
    private let today = NovemberFixture.today

    /// Tests confirmados de 5 km cada `every` días, con VDOT inicial y tasa por semana.
    private func results(count: Int, every: Int, start: Double, perWeek: Double, noise: [Double] = []) -> [PerformanceResult] {
        (0..<count).map { index in
            let daysAgo = (count - 1 - index) * every
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: today))!.addingTimeInterval(8 * 3600)
            let weeksSinceStart = Double(index * every) / 7
            let extra: Double = index < noise.count ? noise[index] : 0
            let vdot: Double = start + perWeek * weeksSinceStart + extra
            return PerformanceResult(date: date, distance: 5000, time: VDOT.raceTime(vdot: vdot, distance: 5000), kind: .test)
        }
    }

    private func adaptation(_ results: [PerformanceResult]) throws -> AdaptationEstimate {
        let model = try #require(RacePerformanceModel.assess(results: results, runs: [], today: today, calendar: calendar))
        return IndividualAdaptationModel.estimate(evidence: model.evidence, referenceRate: IndividualAdaptationModel.baseRate, today: today, calendar: calendar)
    }

    @Test func twoTestsAreNotATrend() throws {
        let test31 = PerformanceResult(date: NovemberFixture.run(10, 31, 18).start, distance: 3026, time: 951, kind: .test)
        let test2 = PerformanceResult(date: NovemberFixture.run(11, 2, 18).start, distance: 4005, time: 1326, kind: .test)
        let estimate = try adaptation([test31, test2])
        #expect(estimate.state == .reference)
        #expect(estimate.dataRate == nil)
        #expect(estimate.individualWeight == 0)
        #expect(estimate.rate == IndividualAdaptationModel.baseRate)
    }

    @Test func threeCloseTestsAreNotEnoughTime() throws {
        let estimate = try adaptation(results(count: 3, every: 4, start: 34, perWeek: 1.0))
        #expect(estimate.state == .reference)
        #expect(estimate.spanDays < IndividualAdaptationModel.minimumSpanDays)
    }

    @Test func realPositiveTrendIsLearned() throws {
        // 6 tests cada 2 semanas mejorando 0,35 VDOT/semana (más rápido que la referencia).
        let estimate = try adaptation(results(count: 6, every: 14, start: 33, perWeek: 0.35))
        #expect(estimate.state != .reference)
        #expect(estimate.rate > IndividualAdaptationModel.baseRate)
        #expect(estimate.rate <= RacePerformanceModel.maximumWeeklyTrend)
        #expect(estimate.individualWeight > 0 && estimate.individualWeight < 1)
        #expect((estimate.dataRate ?? 0) > estimate.rate - 1e-9)
    }

    @Test func realNegativeTrendIsLearned() throws {
        let estimate = try adaptation(results(count: 6, every: 14, start: 36, perWeek: -0.2))
        #expect(estimate.state != .reference)
        #expect((estimate.dataRate ?? 0) < 0)
        #expect(estimate.rate < IndividualAdaptationModel.baseRate)
    }

    @Test func oneAnomalousTestIsDownweighted() throws {
        let clean = try adaptation(results(count: 6, every: 14, start: 34, perWeek: 0.1))
        let anomalous = try adaptation(results(count: 6, every: 14, start: 34, perWeek: 0.1, noise: [0, 0, 0, 6, 0, 0]))
        #expect(anomalous.downweighted >= 1)
        // El test anómalo mueve la tendencia, pero acotado y con más incertidumbre.
        #expect(abs(anomalous.rate - clean.rate) < 0.15)
        #expect(anomalous.rateSD >= clean.rateSD)
    }

    @Test func moreTestsMoreIndividualWeight() throws {
        let few = try adaptation(results(count: 3, every: 14, start: 34, perWeek: 0.1))
        let many = try adaptation(results(count: 8, every: 14, start: 34, perWeek: 0.1))
        #expect(many.individualWeight > few.individualWeight)
        #expect(many.rateSD < few.rateSD)
    }

    @Test func scenariosComeFromThePredictiveDistribution() throws {
        let model = try #require(RacePerformanceModel.assess(results: results(count: 2, every: 2, start: 34.3, perWeek: 0), runs: [], today: today, calendar: calendar))
        let central = GoalProjection.project(performance: model, weeks: 9, compliance: 0.93, runsPerWeek: 4, scenario: .central, complianceSessions: 4, today: today, calendar: calendar)
        let low = GoalProjection.project(performance: model, weeks: 9, compliance: 0.93, runsPerWeek: 4, scenario: .conservative, complianceSessions: 4, today: today, calendar: calendar)
        let high = GoalProjection.project(performance: model, weeks: 9, compliance: 0.93, runsPerWeek: 4, scenario: .optimistic, complianceSessions: 4, today: today, calendar: calendar)
        let z: Double = 1.2816
        #expect(abs((central.projectedVDOT - low.projectedVDOT) - z * central.uncertainty) < 1e-9)
        #expect(abs((high.projectedVDOT - central.projectedVDOT) - z * central.uncertainty) < 1e-9)
        let total = central.varianceParts.values.reduce(0, +)
        #expect(abs(total.squareRoot() - central.uncertainty) < 1e-9)
        // Cuatro sesiones dan más incertidumbre de adherencia que cuarenta.
        let many = GoalProjection.project(performance: model, weeks: 9, compliance: 0.93, runsPerWeek: 4, scenario: .central, complianceSessions: 40, today: today, calendar: calendar)
        #expect((central.varianceParts["adherence"] ?? 0) > (many.varianceParts["adherence"] ?? 0))
    }

    @Test func complianceFactorIsContinuous() {
        let values = stride(from: 0.30, through: 1.0, by: 0.01).map { GoalProbability.gainFactor($0) }
        for (a, b) in zip(values, values.dropFirst()) {
            #expect(b - a <= 0.017 + 1e-9)
            #expect(b >= a)
        }
        #expect(GoalProbability.gainFactor(1) == 1)
        #expect(GoalProbability.gainFactor(0.4) == 0)
    }

    @Test func negativeRatesAreBoundedToo() {
        #expect(GoalProjection.gain(weeks: 10, rate: -0.2) < 0)
        #expect(GoalProjection.gain(weeks: 1000, rate: -0.2) >= -GoalProjection.improvementCap)
        #expect(GoalProjection.gain(weeks: 0, rate: 0.2) == 0)
    }

    @Test func backtestUsesNoFutureData() throws {
        let series = results(count: 6, every: 14, start: 33, perWeek: 0.25)
        let backtest = PredictionBacktest.runProjection(results: series, runs: [], maxHeartRate: nil, calendar: calendar)
        // Cada predicción se hace sin el resultado que predice ni los posteriores.
        for item in backtest.cases {
            let future = series.filter { $0.date >= item.date }
            #expect(!future.isEmpty)
        }
        let truncated = PredictionBacktest.runProjection(results: Array(series.prefix(4)), runs: [], maxHeartRate: nil, calendar: calendar)
        for item in truncated.cases {
            let full = backtest.cases.first { $0.id == item.id }
            #expect(full?.predicted == item.predicted)
        }
    }
}
