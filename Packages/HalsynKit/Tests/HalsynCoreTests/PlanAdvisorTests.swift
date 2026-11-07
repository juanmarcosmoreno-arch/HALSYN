import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
/// Lunes 9 de noviembre de 2026.
private let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!
private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))! }

private let paces = TrainingPaces.from(vdot: 45, target: .tenK)

/// Semana: lun series, mar suave, mié umbral, jue descanso, vie suave, sáb descanso, dom larga.
private func plan(raceInDays: Int = 60, kinds: [SessionKind] = [.intervals, .easy, .tempo, .rest, .easy, .rest, .long]) -> TrainingPlan {
    let sessions = kinds.enumerated().map { index, kind in
        PlannedSession(date: day(index), kind: kind, distance: kind == .rest ? 0 : (kind == .long ? 16_000 : 8000), pace: paces.easy)
    }
    let goal = PlanGoal(distance: .tenK, raceDate: day(raceInDays), runsPerWeek: 5, goalTime: 45 * 60)
    return TrainingPlan(goal: goal, paces: paces, weeks: [PlannedWeek(index: 0, start: day(0), phase: .build, sessions: sessions, level: nil)], createdAt: day(-30), startingWeeklyDistance: 40_000, vdot: 45, lastAdjustment: nil)
}

private func run(_ daysAgo: Int, km: Double, hr: Double) -> WorkoutSummary {
    WorkoutSummary(activity: .outdoorRun, start: calendar.date(byAdding: .hour, value: 7, to: day(-daysAgo))!, duration: km * 330, distanceMeters: km * 1000, averageHeartRate: hr, maxHeartRate: 185, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

private func recovery(recent: [Int], usual: Int = 75) -> [(day: Date, value: Int?)] {
    let history = (3..<28).map { (day: day(-$0), value: Int?(usual)) }
    let last = recent.enumerated().map { (day: day(-$0.offset), value: Int?($0.element)) }
    return history + last
}

@Suite("Plan adaptativo")
struct PlanAdvisorTests {
    @Test func calmWeekOnlyFixesConsecutiveHardDays() {
        // Series lunes y umbral martes: el martes pasa a suave.
        let advice = PlanAdvisor.advise(plan: plan(kinds: [.intervals, .tempo, .easy, .rest, .easy, .rest, .long]), today: today, calendar: calendar, recovery: recovery(recent: [80, 78, 82]), runs: [], maxHeartRate: 185, complaints: [])
        #expect(advice.reasons == [.consecutiveHardDays])
        #expect(advice.adjustments.count == 1)
        #expect(advice.adjustments.first?.original.kind == .tempo)
        #expect(advice.adjustments.first?.adjusted.kind == .easy)
    }

    @Test func noChangeWithoutSignals() {
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: recovery(recent: [80, 78, 82]), runs: [], maxHeartRate: 185, complaints: [])
        #expect(advice.isEmpty)
        #expect(advice.reasons.isEmpty)
    }

    @Test func oneLowRecoveryDayIsNotEnough() {
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: recovery(recent: [35, 78, 82]), runs: [], maxHeartRate: 185, complaints: [])
        #expect(advice.isEmpty)
    }

    @Test func lowRecoveryPlusManyHardSessionsSoftensTheNextHardSession() throws {
        let hardRuns = [run(1, km: 8, hr: 170), run(3, km: 8, hr: 168), run(5, km: 10, hr: 172)]
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: recovery(recent: [40, 45, 70]), runs: hardRuns, maxHeartRate: 185, complaints: [])
        #expect(advice.reasons.contains { if case .lowRecovery = $0 { return true }; return false })
        #expect(advice.reasons.contains(.manyHardSessions(count: 3)))
        let first = try #require(advice.adjustments.first)
        #expect(first.original.date == day(0))
        #expect(first.change == .softened)
        #expect(first.adjusted.distance == 6400)
        // Solo la próxima exigente: el umbral del miércoles sigue.
        let adjusted = PlanAdvisor.apply(advice, to: plan())
        #expect(adjusted.session(on: day(2), calendar: calendar)?.kind == .tempo)
    }

    @Test func moderateComplaintSoftensTheWeek() {
        let complaint = Complaint(date: day(-1), area: .knee, pain: 5)
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: [], runs: [], maxHeartRate: nil, complaints: [complaint])
        #expect(advice.reasons.first == .complaint(area: .knee, pain: 5))
        let adjusted = PlanAdvisor.apply(advice, to: plan())
        #expect(adjusted.weeks[0].sessions.allSatisfy { !$0.kind.isHard })
        #expect(adjusted.session(on: day(6), calendar: calendar)?.distance == 12_800)
    }

    @Test func severeComplaintMeansRestFirst() {
        let complaint = Complaint(date: day(0), area: .achilles, pain: 8)
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: [], runs: [], maxHeartRate: nil, complaints: [complaint])
        let adjusted = PlanAdvisor.apply(advice, to: plan())
        #expect((0..<3).allSatisfy { adjusted.session(on: day($0), calendar: calendar)?.kind == .rest })
        #expect(advice.reasons.first == .severeComplaint(area: .achilles, pain: 8))
    }

    @Test func resolvedOrOldComplaintsDoNotCount() {
        let resolved = Complaint(date: day(-2), area: .knee, pain: 6, resolvedAt: day(-1))
        let old = Complaint(date: day(-20), area: .calf, pain: 6)
        #expect(!resolved.isActive(on: today, calendar: calendar))
        #expect(!old.isActive(on: today, calendar: calendar))
        #expect(PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: [], runs: [], maxHeartRate: nil, complaints: [resolved, old]).isEmpty)
    }

    @Test func volumeSpikeIsMeasuredAgainstYourAverage() throws {
        let previous = (8...35).filter { $0 % 2 == 0 }.map { run($0, km: 5, hr: 140) }      // ~17,5 km/semana
        let spike = [run(1, km: 12, hr: 140), run(2, km: 12, hr: 140), run(4, km: 12, hr: 140)]
        let ratio = try #require(PlanAdvisor.volumeRatio(previous + spike, today: today, calendar: calendar))
        #expect(ratio > 1.5)
    }
}
