import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!
private func daysAgo(_ days: Int, from date: Date = today) -> Date { calendar.date(byAdding: .day, value: -days, to: date)! }

/// Test de 5 km que da el VDOT pedido.
private func test(vdot: Double, on date: Date = today) -> PerformanceResult {
    PerformanceResult(date: date, distance: 5000, time: VDOT.raceTime(vdot: vdot, distance: 5000), kind: .test)
}

private func performance(_ vdot: Double, on date: Date = today) -> PerformanceAssessment? {
    RacePerformanceModel.assess(results: [test(vdot: vdot, on: date)], runs: [], today: date, calendar: calendar)
}

private func makePlan(goalTime: TimeInterval?, weeks: Int = 14) throws -> TrainingPlan {
    let race = calendar.date(byAdding: .day, value: 7 * weeks + 2, to: today)!
    let goal = PlanGoal(distance: .tenK, raceDate: race, runsPerWeek: 4, goalTime: goalTime)
    let estimate = FitnessEstimate(vdot: 44, date: today, source: .result(test(vdot: 44)))
    return try #require(TrainingPlanGenerator.make(goal: goal, estimate: estimate, weeklyDistance: 25_000, today: today, calendar: calendar))
}

private func runs(for plan: TrainingPlan, until day: Date, fraction: Double, skipEvery: Int = 0) -> [WorkoutSummary] {
    plan.weeks.flatMap(\.sessions)
        .filter { $0.kind != .rest && $0.date < calendar.startOfDay(for: day) }
        .enumerated()
        .compactMap { index, session in
            if skipEvery > 0, index % skipEvery == 0 { return nil }
            let meters = max(session.distance, 3000) * fraction
            return WorkoutSummary(activity: .outdoorRun, start: calendar.date(byAdding: .hour, value: 8, to: calendar.startOfDay(for: session.date))!, duration: meters / 1000 * 330, distanceMeters: meters, averageHeartRate: 140, maxHeartRate: 160, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        }
}

@Suite("Factibilidad del objetivo")
struct GoalProbabilityTests {
    @Test func needsAGoalTimeAndAnEstimate() throws {
        #expect(GoalProbability.evaluate(plan: try makePlan(goalTime: nil), performance: performance(44), runs: [], today: today, calendar: calendar) == nil)
        #expect(GoalProbability.evaluate(plan: try makePlan(goalTime: 48 * 60), performance: nil, runs: [], today: today, calendar: calendar) == nil)
    }

    @Test func goalOnTheProjectionIsBalanced() throws {
        var plan = try makePlan(goalTime: 48 * 60)
        let weeks = GoalCoach.trainingWeeks(until: plan.goal.raceDate, distance: .tenK, today: today, calendar: calendar)
        let model = try #require(performance(44))
        let projected = model.currentVDOT + Double(weeks) / 6 * GoalProbability.gainFactor(GoalProbability.assumedCompliance)
        plan.goal.goalTime = VDOT.raceTime(vdot: projected, distance: 10_000)
        let result = try #require(GoalProbability.evaluate(plan: plan, performance: model, runs: [], today: today, calendar: calendar))
        #expect(abs(result.modelValue - 0.5) < 0.03)
        #expect(result.category == .achievable || result.category == .demanding)
        #expect(!result.isCalibrated)
        #expect(result.projectedRange.contains(result.projectedTime))
    }

    @Test func categoriesFollowTheGap() throws {
        var plan = try makePlan(goalTime: 60 * 60)
        let model = performance(44)
        #expect(GoalProbability.evaluate(plan: plan, performance: model, runs: [], today: today, calendar: calendar)?.category == .veryLikely)
        plan.goal.goalTime = 36 * 60
        let hard = try #require(GoalProbability.evaluate(plan: plan, performance: model, runs: [], today: today, calendar: calendar))
        #expect(hard.category == .unrealistic)
        #expect(hard.factors.first { $0.kind == .gap }?.effect == .hinders)
    }

    @Test func complianceMovesTheProjection() throws {
        let plan = try makePlan(goalTime: 46 * 60)
        let later = calendar.date(byAdding: .day, value: 35, to: today)!
        let model = performance(44, on: later)
        let full = try #require(GoalProbability.evaluate(plan: plan, performance: model, runs: runs(for: plan, until: later, fraction: 1), today: later, calendar: calendar))
        let none = try #require(GoalProbability.evaluate(plan: plan, performance: model, runs: [], today: later, calendar: calendar))
        #expect(full.compliance == 1)
        #expect(none.compliance == 0)
        #expect(none.expectedGain == 0)
        #expect(full.projectedTime < none.projectedTime)
        #expect(full.factors.first { $0.kind == .compliance }?.effect == .favors)
        #expect(none.factors.first { $0.kind == .compliance }?.effect == .hinders)
    }

    @Test func noProbabilityAfterTheRace() throws {
        let plan = try makePlan(goalTime: 48 * 60)
        let after = calendar.date(byAdding: .day, value: 3, to: plan.goal.raceDate)!
        #expect(GoalProbability.evaluate(plan: plan, performance: performance(44, on: after), runs: [], today: after, calendar: calendar) == nil)
    }
}

@Suite("Modelo de rendimiento (VDOT + Riegel)")
struct PerformanceModelTests {
    @Test func singleTestMatchesDaniels() throws {
        let model = try #require(performance(50))
        #expect(abs(model.currentVDOT - 50) < 0.01)
        #expect(model.weeklyTrend == nil)
        #expect(!model.hasInterval)
        let fiveK = model.predict(5000)
        #expect(abs(fiveK.vdotTime - VDOT.raceTime(vdot: 50, distance: 5000)) < 0.5)
        // Riegel desde la misma distancia da el mismo tiempo.
        #expect(abs(fiveK.riegelTime - fiveK.vdotTime) < 0.5)
        #expect(fiveK.range == nil)
    }

    @Test func theilSenIgnoresOneOutlier() throws {
        let points: [(x: Double, y: Double)] = [(0, 40), (1, 40.2), (2, 40.4), (3, 55), (4, 40.8)]
        #expect(abs(try #require(RacePerformanceModel.theilSen(points)) - 0.2) < 0.001)
    }

    @Test func improvingTestsShowATrendAndAnInterval() throws {
        let results = [
            test(vdot: 42, on: daysAgo(56)), test(vdot: 43, on: daysAgo(35)),
            test(vdot: 44, on: daysAgo(14)), test(vdot: 44.5, on: daysAgo(2)),
        ]
        let model = try #require(RacePerformanceModel.assess(results: results, runs: [], today: today, calendar: calendar))
        #expect(try #require(model.weeklyTrend) > 0.2)
        #expect(model.currentVDOT > 44)
        #expect(model.hasInterval)
        #expect(model.confidence == .high)
        let range = try #require(model.predict(5000).range)
        #expect(range.contains(model.predict(5000).time))
    }

    @Test func inconsistentTestIsDownweighted() throws {
        let results = [test(vdot: 45, on: daysAgo(20)), test(vdot: 45.2, on: daysAgo(10)), test(vdot: 55, on: daysAgo(5)), test(vdot: 45.1, on: daysAgo(1))]
        let model = try #require(RacePerformanceModel.assess(results: results, runs: [], today: today, calendar: calendar))
        #expect(model.evidence.first { $0.vdot == results[2].vdot ?? 0 }?.isInconsistent == true)
        #expect(model.currentVDOT < 47)
    }

    @Test func personalRiegelExponent() throws {
        // 5 km 20:00 y 10 km 42:00 → k = ln(2520/1200)/ln(2) ≈ 1,07.
        let results = [
            PerformanceResult(date: daysAgo(20), distance: 5000, time: 1200, kind: .race),
            PerformanceResult(date: daysAgo(5), distance: 10_000, time: 2520, kind: .race),
        ]
        let model = try #require(RacePerformanceModel.assess(results: results, runs: [], today: today, calendar: calendar))
        let exponent = try #require(model.personalExponent)
        let expected: Double = log(2520.0 / 1200) / log(2)
        #expect(abs(exponent - expected) < 0.001)
        let riegel: Double = RacePerformanceModel.riegel(time: 1200, from: 5000, to: 10_000, exponent: 1.06)
        let manual: Double = 1200 * pow(2, 1.06)
        #expect(abs(riegel - manual) < 0.001)
    }

    @Test func noEvidenceNoModel() {
        #expect(RacePerformanceModel.assess(results: [], runs: [], today: today, calendar: calendar) == nil)
    }
}
