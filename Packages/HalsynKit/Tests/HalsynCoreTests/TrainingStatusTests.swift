import Foundation
import Testing
@testable import HalsynCore

@Suite("Estado de entrenamiento")
struct TrainingStatusTests {
    private func base() -> TrainingStatusInputs {
        var inputs = TrainingStatusInputs()
        inputs.aerobicVerdict = .unclear
        inputs.vdotChange = 0.2
        inputs.loadRatio = 1.05
        inputs.hardShare = 0.18
        inputs.hrvLowDays = 0
        inputs.restingHighDays = 1
        inputs.shortSleepDays = 1
        inputs.runsLast28 = 12
        return inputs
    }

    @Test func steadyTrainingIsMaintenance() {
        let status = TrainingStatusEngine.evaluate(base())
        #expect(status.state == .maintaining)
        #expect(status.confidence == .high)
        #expect(status.contradicting.isEmpty)
    }

    @Test func clearImprovementIsProductive() {
        var inputs = base()
        inputs.aerobicVerdict = .faster
        let status = TrainingStatusEngine.evaluate(inputs)
        #expect(status.state == .productive)
        #expect(status.supporting.contains(.aerobic(.faster)))
    }

    @Test func oneBadNightDoesNotDecide() {
        var inputs = base()
        inputs.aerobicVerdict = .faster
        inputs.hrvLowDays = 4
        let status = TrainingStatusEngine.evaluate(inputs)
        // Una sola señal de recuperación en contra: sigue productivo, con contradicción.
        #expect(status.state == .productive)
        #expect(status.contradicting.contains(.hrv(lowDays: 4)))
    }

    @Test func twoRecoverySignalsNeedRecovery() {
        var inputs = base()
        inputs.aerobicVerdict = .faster
        inputs.hrvLowDays = 4
        inputs.restingHighDays = 3
        let status = TrainingStatusEngine.evaluate(inputs)
        #expect(status.state == .recoveryNeeded)
        #expect(status.contradicting.contains(.aerobic(.faster)))
    }

    @Test func loadJumpIsHighLoad() {
        var inputs = base()
        inputs.loadRatio = 1.5
        #expect(TrainingStatusEngine.evaluate(inputs).state == .highLoad)
    }

    @Test func decliningOrContradictoryIsUncertain() {
        var inputs = base()
        inputs.aerobicVerdict = .slower
        #expect(TrainingStatusEngine.evaluate(inputs).state == .uncertain)
        inputs.aerobicVerdict = .faster
        inputs.vdotChange = -1.5
        inputs.vdotChangeIsClear = true
        #expect(TrainingStatusEngine.evaluate(inputs).state == .uncertain)
    }

    @Test func fewRunsAndNoTrendsIsInsufficient() {
        var inputs = TrainingStatusInputs()
        inputs.runsLast28 = 2
        inputs.loadRatio = 1.0
        let status = TrainingStatusEngine.evaluate(inputs)
        #expect(status.state == .insufficientData)
        #expect(status.confidence == .low)
        #expect(status.missing.contains("hrv"))
    }
}
