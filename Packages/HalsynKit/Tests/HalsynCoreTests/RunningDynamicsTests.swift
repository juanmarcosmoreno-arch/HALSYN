import Foundation
import Testing
@testable import HalsynCore

@Suite("Técnica de carrera")
struct RunningDynamicsTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_790_000_000)

    private func run(daysAgo: Int, speed: Double, cadence: Double?, stride: Double? = nil, contact: Double? = nil, power: Double? = nil, indoor: Bool = false) -> WorkoutSummary {
        var workout = WorkoutSummary(activity: indoor ? .indoorRun : .outdoorRun, start: today.addingTimeInterval(Double(-daysAgo) * 86_400), duration: 1800, distanceMeters: speed * 30, averageHeartRate: 150, maxHeartRate: 170, activeEnergyKilocalories: nil, averageCadence: cadence, origin: .demo)
        workout.dynamics = RunningDynamics(strideLength: stride, groundContactTime: contact, power: power)
        return workout
    }

    @Test func fasterRunsAloneAreNotAChange() throws {
        // Misma relación cadencia–velocidad (cadencia = 120 + 0,25 × v): las
        // recientes son más rápidas, así que su cadencia es más alta sin cambio de técnica.
        let previous = [60, 63, 66, 69].map { run(daysAgo: $0, speed: 170, cadence: 120 + 0.25 * 170 + Double($0 % 2)) }
        let recent = [2, 5, 8, 11].map { run(daysAgo: $0, speed: 200, cadence: 120 + 0.25 * 200 + Double($0 % 2)) }
        let summary = try #require(RunningDynamicsAnalysis.summary(.cadence, runs: previous + recent, today: today, calendar: calendar))
        #expect(summary.recentMean > 169)
        #expect(summary.change == .unclear)
    }

    @Test func realChangeAtSameSpeedIsDetected() throws {
        let previous = [60, 63, 66, 69].map { run(daysAgo: $0, speed: 180, cadence: 160 + Double($0 % 3)) }
        let recent = [2, 5, 8, 11].map { run(daysAgo: $0, speed: 180, cadence: 172 + Double($0 % 3)) }
        let summary = try #require(RunningDynamicsAnalysis.summary(.cadence, runs: previous + recent, today: today, calendar: calendar))
        #expect(summary.change == .higher)
        #expect((summary.adjustedChange ?? 0) > 8)
    }

    @Test func missingSensorDataIsNotInvented() {
        let runs = [2, 5, 8].map { run(daysAgo: $0, speed: 180, cadence: 165) }
        #expect(RunningDynamicsAnalysis.summary(.groundContactTime, runs: runs, today: today, calendar: calendar) == nil)
        #expect(RunningDynamicsAnalysis.summary(.cadence, runs: runs, today: today, calendar: calendar)?.change == nil)
        let implausible = [2, 5, 8].map { run(daysAgo: $0, speed: 180, cadence: 165, contact: 2000) }
        #expect(RunningDynamicsAnalysis.summary(.groundContactTime, runs: implausible, today: today, calendar: calendar) == nil)
    }

    @Test func speedPerWattIsDerivedFromPower() throws {
        let runs = [2, 5, 8].map { run(daysAgo: $0, speed: 180, cadence: 165, power: 240) }
        let summary = try #require(RunningDynamicsAnalysis.summary(.speedPerWatt, runs: runs, today: today, calendar: calendar))
        #expect(abs(summary.recentMean - 0.75) < 0.001)
    }
}
