import Foundation
import Testing
@testable import HalsynCore

/// Regresión con los casos de la exportación de noviembre de 2026
/// (anonimizados: sin nombres, zapatillas ni identificadores reales).
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Montevideo")!
    calendar.firstWeekday = 2
    return calendar
}()
private func date(_ day: Int, _ month: Int, hour: Int = 18) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private enum Fixture {
    static let workout31 = WorkoutSummary(activity: .outdoorRun, start: date(31, 10), duration: 951, distanceMeters: 3026, averageHeartRate: 176, maxHeartRate: 182, activeEnergyKilocalories: nil, averageCadence: 163, origin: .demo)
    static let workout2 = WorkoutSummary(activity: .outdoorRun, start: date(2, 11), duration: 1326, distanceMeters: 4005, averageHeartRate: 171, maxHeartRate: 185, activeEnergyKilocalories: nil, averageCadence: 161, origin: .demo)
    static let manual31 = PerformanceResult(date: date(31, 10, hour: 0), distance: 3000, time: 951, kind: .test)
    static let marked31 = PerformanceResult(date: date(31, 10), distance: 3026, time: 951, kind: .test, workoutID: workout31.id)
    static let marked2 = PerformanceResult(date: date(2, 11), distance: 4005, time: 1326, kind: .test, workoutID: workout2.id)
    static let today = date(7, 11, hour: 19)
    static let runs = [workout31, workout2]
}

@Suite("Auditoría de noviembre: VDOT, duplicados y cumplimiento")
struct NovemberAuditTests {
    // MARK: VDOT

    @Test func combinedVDOTIsAWeightedMeanAndSaysSo() throws {
        let model = try #require(RacePerformanceModel.assess(results: [Fixture.manual31, Fixture.marked31, Fixture.marked2], runs: Fixture.runs, maxHeartRate: 186, today: Fixture.today, calendar: calendar))
        #expect(model.isWeightedCombination)
        let counted = model.countedEvidence
        #expect(counted.count == 2)
        // La media ponderada de los valores usados reproduce exactamente el VDOT.
        let total = counted.map(\.weight).reduce(0, +)
        let mean = counted.map { $0.weight * ($0.valueUsed ?? 0) }.reduce(0, +) / total
        #expect(abs(mean - model.currentVDOT) < 1e-9)
        // El test del 2 nov tiene VDOT ≈ 33,7 y el combinado ≈ 34,4: no son el mismo número.
        let test2 = try #require(counted.first { $0.id == Fixture.marked2.id })
        #expect(abs(test2.vdot - model.currentVDOT) > 0.3)
        // El peso es el producto de sus factores.
        let factors = try #require(test2.factors)
        #expect(abs(factors.product - test2.weight) < 1e-9)
        #expect(factors.distance == 1)
        #expect(factors.quality == 1)
    }

    @Test func slowerValidTestLowersTheEstimate() throws {
        let before = try #require(RacePerformanceModel.assess(results: [Fixture.marked31], runs: Fixture.runs, today: Fixture.today, calendar: calendar))
        let after = try #require(RacePerformanceModel.assess(results: [Fixture.marked31, Fixture.marked2], runs: Fixture.runs, today: Fixture.today, calendar: calendar))
        #expect(after.currentVDOT < before.currentVDOT)
    }

    @Test func shortAndTreadmillTestsWeighLess() throws {
        let short = PerformanceResult(date: date(2, 11), distance: 1000, time: 270, kind: .test)
        let treadmill = WorkoutSummary(activity: .indoorRun, start: date(3, 11), duration: 1300, distanceMeters: 4000, averageHeartRate: 172, maxHeartRate: 184, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
        let treadmillTest = PerformanceResult(date: date(3, 11), distance: 4000, time: 1300, kind: .test, workoutID: treadmill.id)
        let model = try #require(RacePerformanceModel.assess(results: [short, treadmillTest], runs: [treadmill], maxHeartRate: 186, today: Fixture.today, calendar: calendar))
        #expect(model.evidence.first { $0.id == short.id }?.factors?.distance == 0.6)
        let indoor = try #require(model.evidence.first { $0.id == treadmillTest.id }?.factors)
        #expect(indoor.quality == 0.8)
        #expect(indoor.qualityNotes == [.treadmill])
    }

    @Test func lowHeartRateTestWeighsLess() throws {
        let easyTest = WorkoutSummary(activity: .outdoorRun, start: date(3, 11), duration: 1500, distanceMeters: 4000, averageHeartRate: 140, maxHeartRate: 160, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
        let result = PerformanceResult(date: date(3, 11), distance: 4000, time: 1500, kind: .test, workoutID: easyTest.id)
        let model = try #require(RacePerformanceModel.assess(results: [result], runs: [easyTest], maxHeartRate: 186, today: Fixture.today, calendar: calendar))
        #expect(model.evidence.first?.factors?.qualityNotes == [.lowHeartRate])
    }

    @Test func trainingEffortsCannotOutweighTests() throws {
        // Varios entrenamientos a tope más rápidos que el único test.
        let efforts = (3...6).map { day in
            WorkoutSummary(activity: .outdoorRun, start: date(day, 11, hour: 7), duration: 1140, distanceMeters: 4000, averageHeartRate: 176, maxHeartRate: 184, activeEnergyKilocalories: nil, averageCadence: 170, origin: .demo)
        }
        let model = try #require(RacePerformanceModel.assess(results: [Fixture.marked2], runs: [Fixture.workout2] + efforts, maxHeartRate: 186, today: Fixture.today, calendar: calendar))
        let training = model.evidence.filter { $0.kind == .trainingEffort && $0.weight > 0 }.map(\.weight).reduce(0, +)
        let official = model.evidence.filter { $0.kind != .trainingEffort && $0.weight > 0 }.map(\.weight).reduce(0, +)
        #expect(training > 0)
        #expect(training <= RacePerformanceModel.trainingShareCap * official + 1e-9)
        #expect(model.evidence.contains { ($0.factors?.cap ?? 1) < 1 })
    }

    // MARK: Duplicados

    @Test func sameHealthKitWorkoutIsAlwaysADuplicate() {
        let a = PerformanceResult(date: date(31, 10), distance: 3026, time: 951, kind: .test, workoutID: Fixture.workout31.id)
        let b = PerformanceResult(date: date(1, 11), distance: 3100, time: 990, kind: .race, workoutID: Fixture.workout31.id)
        #expect(RacePerformanceModel.deduplicated([a, b], calendar: calendar).kept.count == 1)
    }

    @Test func manualCorrectionKeepsBoth() throws {
        let results = [Fixture.manual31, Fixture.marked31]
        #expect(RacePerformanceModel.deduplicated(results, calendar: calendar).kept.count == 1)
        #expect(RacePerformanceModel.deduplicated(results, distinct: [Fixture.manual31.id], calendar: calendar).kept.count == 2)
        let model = try #require(RacePerformanceModel.assess(results: results, runs: Fixture.runs, distinct: [Fixture.manual31.id], today: Fixture.today, calendar: calendar))
        #expect(model.officialCount == 2)
    }

    // MARK: Cumplimiento

    private func plan() -> TrainingPlan {
        let paces = TrainingPaces.from(vdot: 34, target: .fiveK)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let sessions = [0, 2, 4, 6].map { offset in
            PlannedSession(date: calendar.date(byAdding: .day, value: offset, to: monday)!, kind: .easy, distance: 4000, pace: paces.easy)
        }
        let goal = PlanGoal(distance: .fiveK, raceDate: date(18, 1, hour: 9).addingTimeInterval(365 * 86_400), runsPerWeek: 4, goalTime: 1500)
        return TrainingPlan(goal: goal, paces: paces, weeks: [PlannedWeek(index: 0, start: monday, phase: .build, sessions: sessions, level: nil)], createdAt: monday, startingWeeklyDistance: 15_000, vdot: 34, lastAdjustment: nil)
    }

    private func run(_ day: Int) -> WorkoutSummary {
        WorkoutSummary(activity: .outdoorRun, start: date(day, 11, hour: 7), duration: 1500, distanceMeters: 4000, averageHeartRate: 160, maxHeartRate: 175, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
    }

    @Test func allScheduledSessionsDoneShowsOneHundredPercent() {
        // Sesiones lun 2, mié 4, vie 6 hechas; dom 8 todavía no llegó.
        let adherence = TrainingAdherence.evaluate(plan: plan(), runs: [run(2), run(4), run(6)], today: date(7, 11), calendar: calendar)
        #expect(adherence.sessionsSummary == "3 / 3 · 100 %")
        #expect(adherence.missed == 0)
        #expect(adherence.targetRunsPerWeek == 4)
    }

    @Test func illnessDoesNotCountAsMissed() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let friday = calendar.date(byAdding: .day, value: 4, to: monday)!
        let excused = TrainingAdherence.evaluate(plan: plan(), runs: [run(2)], today: date(7, 11), calendar: calendar, skips: [wednesday: .illness], healthDays: [friday])
        #expect(excused.planned == 1)
        #expect(excused.excused == 2)
        #expect(excused.sessionsSummary == "1 / 1 · 100 %")
        let travel = TrainingAdherence.evaluate(plan: plan(), runs: [run(2)], today: date(7, 11), calendar: calendar, skips: [wednesday: .travel])
        #expect(travel.planned == 3)
        #expect(travel.missed == 2)
        #expect(travel.skipReasons[.travel] == 1)
    }
}
