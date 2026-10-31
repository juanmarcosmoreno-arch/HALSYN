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
