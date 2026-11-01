import Foundation
import Testing
@testable import HalsynCore

@Suite("Calentamiento y calma fuera del entrenamiento grabado")
struct IntervalSessionLayoutTests {
    private let plan = IntervalPlan(id: "6x400", name: "6 × 400 m", warmup: .time(600), work: .distance(400), recovery: .time(90), repeats: 6, cooldown: .time(300))

    @Test func warmupAndCooldownLeaveTheRecordedPlan() {
        let layout = IntervalSessionLayout(plan: plan, measuresRecovery: true, defaultRecoveryMinutes: 2)
        #expect(layout.warmup == .time(600))
        #expect(layout.recorded.warmup == nil && layout.recorded.cooldown == nil)
        #expect(layout.recorded.steps.first?.kind == .work)
        #expect(layout.recorded.steps.last?.kind == .work)
        #expect(layout.recoveryMinutes == 5)
    }

    @Test func cooldownStaysWithoutRecovery() {
        let layout = IntervalSessionLayout(plan: plan, measuresRecovery: false, defaultRecoveryMinutes: 2)
        #expect(layout.recoveryMinutes == nil)
        #expect(layout.recorded.cooldown == .time(300))
        #expect(layout.recorded.warmup == nil)
    }

    @Test func recoveryMinutes() {
        #expect(IntervalSessionLayout.minutes(for: .distance(2000), default: 2) == 2)
        #expect(IntervalSessionLayout.minutes(for: .time(20), default: 2) == 1)
        #expect(IntervalSessionLayout.minutes(for: .time(1800), default: 2) == 10)
        #expect(IntervalSessionLayout.minutes(for: .open, default: 5) == 5)
    }
}

@Suite("Tipos de entrenamiento")
struct WorkoutStyleTests {
    @Test func templatesAndLabels() {
        let hills = WorkoutStyle.hills.template(id: "h", name: "R")
        #expect(hills.kind == .hills && hills.work == .time(45) && hills.repeats == 8)
        #expect(hills.kind.label(for: .work) == "SUBIDA" && hills.kind.title(for: .recovery) == "Bajada")
        #expect(WorkoutStyle.fartlek.label(for: .warmup) == "CALENTAR")
        let long = WorkoutStyle.long.template(id: "l", name: "F")
        #expect(long.steps.count == 1 && long.steps[0].kind == .work)
        #expect(IntervalPlanFormatter.summary(long, locale: Locale(identifier: "es_ES")) == "15 km")
    }

    @Test func oldPlansDecodeAsIntervals() throws {
        let old = #"{"id":"x","name":"x","work":{"distance":{"_0":400}},"recovery":{"time":{"_0":90}},"repeats":4}"#
        let plan = try JSONDecoder().decode(IntervalPlan.self, from: Data(old.utf8))
        #expect(plan.style == nil && plan.kind == .intervals)
        let encoded = try JSONEncoder().encode(WorkoutStyle.hills.template(id: "h", name: "R"))
        #expect(try JSONDecoder().decode(IntervalPlan.self, from: encoded).kind == .hills)
    }
}

@Suite("Color del anillo del reloj")
struct WorkoutRingColorTests {
    @Test func defaultsToGreenAndContrastsWithBlack() throws {
        #expect(RunSettings().ringColor == .green)
        let black = HalsynRGBColor(hex: 0x000000)
        for color in WorkoutRingColor.allCases {
            guard let rgb = color.rgb else { continue }
            // Muy por encima de 4,5:1 (WCAG AA) sobre el negro del reloj.
            #expect(rgb.contrastRatio(with: black) >= 7, "\(color)")
        }
        let old = try JSONEncoder().encode(RunSettings())
        #expect(try JSONDecoder().decode(RunSettings.self, from: old).ringColor == .green)
    }
}

@Suite("Carrera libre con objetivo")
struct GoalRunTests {
    @Test func goalRunPlans() throws {
        #expect(IntervalPlan.goalRun(distance: nil, pace: nil, name: "x") == nil)
        let distance = try #require(IntervalPlan.goalRun(distance: 5000, pace: nil, name: "x"))
        #expect(distance.isGoalRun && distance.steps.count == 1 && distance.steps[0].goal == .distance(5000) && distance.workPace == nil)
        let pace = try #require(IntervalPlan.goalRun(distance: 0, pace: Pace(secondsPerKilometer: 300), name: "x"))
        #expect(pace.steps[0].goal == .open && pace.steps[0].paceTarget == PaceRange(fastest: 295, slowest: 305))
    }

    @Test func paceStatus() {
        let range = PaceRange(center: Pace(secondsPerKilometer: 300), tolerance: 5)
        #expect(range.status(of: Pace(secondsPerKilometer: 310)) == .slower)
        #expect(range.status(of: Pace(secondsPerKilometer: 302)) == .onPace)
        #expect(range.status(of: Pace(secondsPerKilometer: 290)) == .faster)
    }
}

@Suite("Carrera libre con objetivo · vueltas")
struct GoalRunLapTests {
    @Test func lapDoesNotEndThePaceGoal() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = try #require(IntervalPlan.goalRun(distance: nil, pace: Pace(secondsPerKilometer: 300), name: "x"))
        var tracker = RunSessionTracker(settings: RunSettings(), plan: plan)
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.updateDistance(total: 1000, at: t0.addingTimeInterval(300))
        tracker.markLap(at: t0.addingTimeInterval(300))
        let snapshot = tracker.snapshot(at: t0.addingTimeInterval(300))
        #expect(snapshot.interval?.step.kind == .work)
        #expect(snapshot.paceTarget == PaceRange(fastest: 295, slowest: 305))
    }
}

@Suite("Fuerza para corredores")
struct RunnerStrengthTests {
    @Test func everyGroupHasExercises() {
        for group in StrengthExercise.Group.allCases {
            #expect(!StrengthExercise.exercises(in: group).isEmpty, "\(group)")
        }
        #expect(Set(StrengthExercise.all.map(\.id)).count == StrengthExercise.all.count)
    }
}
