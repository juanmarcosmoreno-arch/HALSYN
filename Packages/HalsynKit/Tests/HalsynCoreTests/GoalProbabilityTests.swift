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

private func makePlan(goalTime: TimeInterval?, weeks: Int = 14) throws -> TrainingPlan {
    let race = calendar.date(byAdding: .day, value: 7 * weeks + 2, to: today)!
    let goal = PlanGoal(distance: .tenK, raceDate: race, runsPerWeek: 4, goalTime: goalTime)
    let estimate = FitnessEstimate(vdot: 44, date: today, source: .result(PerformanceResult(date: today, distance: 5000, time: 23 * 60, kind: .test)))
    return try #require(TrainingPlanGenerator.make(goal: goal, estimate: estimate, weeklyDistance: 25_000, today: today, calendar: calendar))
}

private func fresh(_ vdot: Double, on date: Date = today) -> FitnessEstimate {
    FitnessEstimate(vdot: vdot, date: date, source: .result(PerformanceResult(date: date, distance: 5000, time: 23 * 60, kind: .test)))
}

/// Carreras que cumplen (o no) las sesiones del plan hasta `day`.
private func runs(for plan: TrainingPlan, until day: Date, fraction: Double, skipEvery: Int = 0) -> [WorkoutSummary] {
    plan.weeks.flatMap(\.sessions)
        .filter { $0.kind != .rest && $0.date < calendar.startOfDay(for: day) }
        .enumerated()
        .compactMap { index, session in
            if skipEvery > 0, index % skipEvery == 0 { return nil }
            let meters = max(session.distance, 3000) * fraction
            return WorkoutSummary(activity: .outdoorRun, start: calendar.date(byAdding: .hour, value: 8, to: calendar.startOfDay(for: session.date))!, duration: meters / 1000 * 330, distanceMeters: meters, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        }
}

@Suite("Probabilidad de llegar al objetivo")
struct GoalProbabilityTests {
    @Test func needsAGoalTimeAndAnEstimate() throws {
        let plan = try makePlan(goalTime: nil)
        #expect(GoalProbability.evaluate(plan: plan, estimate: fresh(44), runs: [], today: today, calendar: calendar) == nil)
        let timed = try makePlan(goalTime: 48 * 60)
        #expect(GoalProbability.evaluate(plan: timed, estimate: nil, runs: [], today: today, calendar: calendar) == nil)
    }

    @Test func goalOnTheProjectionIsACoinFlip() throws {
        // Objetivo exactamente en la forma prevista: 50 %, ni optimista ni pesimista.
        var plan = try makePlan(goalTime: 48 * 60)
        let weeks = GoalCoach.trainingWeeks(until: plan.goal.raceDate, distance: .tenK, today: today, calendar: calendar)
        let projected = 44 + Double(weeks) / 6 * GoalProbability.gainFactor(GoalProbability.assumedCompliance)
        plan.goal.goalTime = VDOT.raceTime(vdot: projected, distance: 10_000)
        let probability = try #require(GoalProbability.evaluate(plan: plan, estimate: fresh(44), runs: [], today: today, calendar: calendar))
        #expect(abs(probability.value - 0.5) < 0.03)
        #expect(probability.level == .possible)
        #expect(probability.compliance == nil)
    }

    @Test func easyAndHardGoalsAreClampedAndColored() throws {
        var plan = try makePlan(goalTime: 60 * 60)
        let easy = try #require(GoalProbability.evaluate(plan: plan, estimate: fresh(44), runs: [], today: today, calendar: calendar))
        #expect(easy.value == GoalProbability.maximum)
        #expect(easy.level == .likely)
        plan.goal.goalTime = 36 * 60
        let hard = try #require(GoalProbability.evaluate(plan: plan, estimate: fresh(44), runs: [], today: today, calendar: calendar))
        #expect(hard.value == GoalProbability.minimum)
        #expect(hard.level == .unlikely)
    }

    @Test func complianceMovesTheProbability() throws {
        let plan = try makePlan(goalTime: 46 * 60)
        let later = calendar.date(byAdding: .day, value: 35, to: today)!
        let estimate = fresh(44, on: later)
        let full = try #require(GoalProbability.evaluate(plan: plan, estimate: estimate, runs: runs(for: plan, until: later, fraction: 1), today: later, calendar: calendar))
        let half = try #require(GoalProbability.evaluate(plan: plan, estimate: estimate, runs: runs(for: plan, until: later, fraction: 1, skipEvery: 2), today: later, calendar: calendar))
        let none = try #require(GoalProbability.evaluate(plan: plan, estimate: estimate, runs: [], today: later, calendar: calendar))
        #expect(full.compliance == 1)
        #expect(full.sessionsDone == full.sessionsPlanned)
        #expect(try #require(half.compliance) < 0.6)
        #expect(none.compliance == 0)
        #expect(none.expectedGain == 0)
        #expect(full.value > half.value)
        #expect(half.value > none.value)
    }

    @Test func betterFitnessRaisesTheProbability() throws {
        let plan = try makePlan(goalTime: 46 * 60)
        let now = try #require(GoalProbability.evaluate(plan: plan, estimate: fresh(44), runs: [], today: today, calendar: calendar))
        let faster = try #require(GoalProbability.evaluate(plan: plan, estimate: fresh(46), runs: [], today: today, calendar: calendar))
        #expect(faster.value > now.value)
    }

    @Test func trainingEstimatesAreLessCertain() throws {
        let plan = try makePlan(goalTime: 46 * 60 + 30)
        let test = try #require(GoalProbability.evaluate(plan: plan, estimate: fresh(44), runs: [], today: today, calendar: calendar))
        let training = try #require(GoalProbability.evaluate(plan: plan, estimate: FitnessEstimate(vdot: 44, date: today, source: .training(runs: 4)), runs: [], today: today, calendar: calendar))
        #expect(training.uncertainty > test.uncertainty)
        // Objetivo por debajo de la forma prevista: más incertidumbre, menos seguro.
        #expect(training.value < test.value)
    }

    @Test func noProbabilityAfterTheRace() throws {
        let plan = try makePlan(goalTime: 48 * 60)
        let after = calendar.date(byAdding: .day, value: 3, to: plan.goal.raceDate)!
        #expect(GoalProbability.evaluate(plan: plan, estimate: fresh(44, on: after), runs: [], today: after, calendar: calendar) == nil)
    }
}
