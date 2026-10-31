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
private let created = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!

@Suite("SPRING · editar la semana del plan")
struct PlanEditingTests {
    private func plan() throws -> TrainingPlan {
        let race = calendar.date(byAdding: .day, value: 7 * 10 + 2, to: created)!
        return try #require(TrainingPlanGenerator.make(goal: PlanGoal(distance: .tenK, raceDate: race, runsPerWeek: 4), tenKTime: 50 * 60, weeklyDistance: 25_000, today: created, calendar: calendar))
    }

    /// Lunes de la segunda semana del plan, a media mañana.
    private func monday(_ plan: TrainingPlan) -> Date {
        calendar.date(byAdding: .hour, value: 10, to: plan.weeks[1].start)!
    }

    @Test func movesToAFreeDayAndSwapsWithABusyOne() throws {
        let plan = try plan()
        let today = monday(plan)
        let sessions = plan.weeks[1].sessions.filter { $0.kind != .rest }
        let first = try #require(sessions.first)
        let days = plan.editableDays(today: today, calendar: calendar)
        #expect(days.count == 7)
        let free = try #require(days.first { day in plan.session(on: day, calendar: calendar) == nil && !calendar.isDate(day, inSameDayAs: first.date) })
        let moved = try #require(plan.moving(sessionOn: first.date, to: free, today: today, calendar: calendar))
        #expect(moved.session(on: free, calendar: calendar)?.kind == first.kind)
        #expect(moved.session(on: first.date, calendar: calendar) == nil)
        #expect(moved.weeks[1].distance == plan.weeks[1].distance)

        let second = sessions[1]
        let swapped = try #require(plan.moving(sessionOn: first.date, to: second.date, today: today, calendar: calendar))
        #expect(swapped.session(on: second.date, calendar: calendar)?.kind == first.kind)
        #expect(swapped.session(on: first.date, calendar: calendar)?.kind == second.kind)
        #expect(swapped.session(on: first.date, calendar: calendar)?.distance == second.distance)
    }

    @Test func onlyThisWeekFromToday() throws {
        let plan = try plan()
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday(plan))!
        let monday = monday(plan)
        #expect(plan.editableDays(today: wednesday, calendar: calendar).count == 5)
        #expect(!plan.canEdit(monday, today: wednesday, calendar: calendar))
        let nextWeek = plan.weeks[2].sessions[0].date
        #expect(!plan.canEdit(nextWeek, today: wednesday, calendar: calendar))
        #expect(plan.moving(sessionOn: plan.weeks[2].sessions[0].date, to: wednesday, today: wednesday, calendar: calendar) == nil)
    }

    @Test func resizeAndSkip() throws {
        let plan = try plan()
        let today = monday(plan)
        let easy = try #require(plan.weeks[1].sessions.first { $0.kind == .easy })
        let shorter = easy.with(.distance(easy.distance - 2000))
        let edited = try #require(plan.replacing(sessionOn: easy.date, with: shorter, today: today, calendar: calendar))
        #expect(edited.session(on: easy.date, calendar: calendar)?.distance == easy.distance - 2000)
        let skipped = try #require(plan.skipping(sessionOn: easy.date, today: today, calendar: calendar))
        #expect(skipped.session(on: easy.date, calendar: calendar)?.kind == .rest)
    }

    @Test func volumeChanges() {
        let day = created
        let intervals = PlannedSession(date: day, kind: .intervals, distance: 9000, repeats: 6, repeatDistance: 800)
        let more = intervals.with(.repeats(8))
        #expect(more.repeats == 8 && more.distance == 10_600)
        #expect(intervals.with(.repeats(1)).repeats == 2)
        let tempo = PlannedSession(date: day, kind: .tempo, distance: 9000, repeats: 1, repeatDistance: 4000)
        #expect(tempo.with(.block(5000)).distance == 10_000)
        let easy = PlannedSession(date: day, kind: .easy, distance: 8000, pace: PaceRange(fastest: 330, slowest: 390))
        #expect(abs((easy.estimatedDuration ?? 0) - 8 * 360) < 0.01)
        #expect(PlannedSession(date: day, kind: .rest, distance: 0).volume == nil)
    }
}
