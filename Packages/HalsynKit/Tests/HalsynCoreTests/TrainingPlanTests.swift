import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
/// Viernes 23 de octubre de 2026.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!

private func plan(_ distance: RaceDistance, weeks: Int, runs: Int = 4, weekly: Double = 25_000) throws -> TrainingPlan {
    let race = calendar.date(byAdding: .day, value: 7 * weeks + 2, to: today)!
    return try #require(TrainingPlanGenerator.make(goal: PlanGoal(distance: distance, raceDate: race, runsPerWeek: runs), tenKTime: 50 * 60, weeklyDistance: weekly, today: today, calendar: calendar))
}

@Suite("SPRING · plan de entrenamiento")
struct TrainingPlanTests {
    @Test func pacesFromTenK() {
        let paces = TrainingPaces.from(tenK: 50 * 60, target: .tenK)
        // 10 km en 50:00 → 5:00/km; suave 6:00–6:30; series ≈ ritmo de 5 km (≈4:48).
        #expect(paces.easy.fastest == 360 && paces.easy.slowest == 390)
        #expect(abs(paces.interval.center.secondsPerKilometer - 287.7) < 1)
        #expect(paces.tempo.center.secondsPerKilometer > 287 && paces.tempo.center.secondsPerKilometer < 320)
        #expect(paces.race.secondsPerKilometer == 300)
    }

    @Test func volumeGrowsAtMostEightPercent() throws {
        let plan = try plan(.half, weeks: 12)
        #expect(plan.weeks.count >= 12)
        let normal = plan.weeks.filter { $0.phase == .base || $0.phase == .build }
        for (a, b) in zip(normal, normal.dropFirst()) where b.index == a.index + 1 {
            #expect(b.distance <= a.distance * 1.08 + 2500)
        }
        #expect(plan.weeks.contains { $0.phase == .recovery })
        #expect(plan.weeks.filter { $0.phase == .taper }.count == 2)
        #expect(plan.weeks.last?.phase == .race)
    }

    @Test func sessionsPerWeekAndRaceDay() throws {
        let plan = try plan(.tenK, weeks: 8, runs: 4)
        let build = try #require(plan.weeks.first { $0.phase == .build })
        #expect(build.sessions.count == 4)
        #expect(build.sessions.filter { $0.kind.isHard }.count == 2)
        #expect(build.sessions.filter { $0.kind == .long }.count == 1)
        let last = try #require(plan.weeks.last?.sessions.last)
        #expect(last.distance == 10_000)
        #expect(calendar.isDate(last.date, inSameDayAs: plan.goal.raceDate))
    }

    @Test func longRunIsCapped() throws {
        let plan = try plan(.fiveK, weeks: 10, weekly: 60_000)
        let longest = plan.weeks.flatMap(\.sessions).filter { $0.kind == .long && $0.date < plan.goal.raceDate }.map(\.distance).max() ?? 0
        #expect(longest <= 10_000)
    }

    @Test func tooCloseRaceHasNoPlan() {
        let race = calendar.date(byAdding: .day, value: 10, to: today)!
        #expect(TrainingPlanGenerator.make(goal: PlanGoal(distance: .tenK, raceDate: race, runsPerWeek: 3), tenKTime: 3000, weeklyDistance: 20_000, today: today, calendar: calendar) == nil)
    }

    @Test func adaptationSoftensOrRests() throws {
        let paces = TrainingPaces.from(tenK: 3000, target: .tenK)
        let intervals = PlannedSession(date: today, kind: .intervals, distance: 9000, repeats: 6, repeatDistance: 800, pace: paces.interval)
        #expect(PlanAdaptation.adapt(intervals, guidance: .push, paces: paces).change == .none)
        let soft = PlanAdaptation.adapt(intervals, guidance: .easy, paces: paces)
        #expect(soft.change == .softened && soft.session.kind == .easy && soft.session.distance == 6500)
        #expect(PlanAdaptation.adapt(intervals, guidance: .rest, paces: paces).session.kind == .rest)
    }

    @Test func watchPlanFromSession() throws {
        let paces = TrainingPaces.from(tenK: 3000, target: .tenK)
        let session = PlannedSession(date: today, kind: .intervals, distance: 9000, repeats: 6, repeatDistance: 800, pace: paces.interval)
        let watch = try #require(PlanAdaptation.intervalPlan(for: session, id: "plan", name: "Series"))
        #expect(watch.repeats == 6)
        #expect(watch.work == .distance(800))
        #expect(watch.steps.count == 1 + 6 + 5 + 1)
    }

    @Test func codableRoundTrip() throws {
        let plan = try plan(.marathon, weeks: 16, runs: 5)
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(TrainingPlan.self, from: data) == plan)
        #expect(plan.weeks.filter { $0.phase == .taper }.count == 3)
    }
}
