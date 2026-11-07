import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}()
private let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 20))!

@Suite("Zonas por FC umbral")
struct ThresholdZoneTests {
    @Test func frielZonesFromThreshold() {
        let config = HeartRateZoneConfiguration(method: .lactateThreshold, maxSource: .manual, maxHeartRate: 190, thresholdHeartRate: 170)
        #expect(config.effectiveMethod == .lactateThreshold)
        let zones = config.zones
        #expect(zones.map(\.lowerBound) == [111, 145, 153, 162, 170])
        #expect(zones.last?.upperBound == 190)
        #expect(config.zone(for: 168) == 4)
        #expect(!config.isApproximate)
    }

    @Test func withoutThresholdFallsBackAndObservedMaxIsApproximate() {
        let config = HeartRateZoneConfiguration(method: .lactateThreshold, maxSource: .observed, maxHeartRate: 185)
        #expect(config.effectiveMethod == .percentOfMax)
        #expect(config.isApproximate)
        #expect(config.zones.first?.lowerBound == 93)
    }
}

@Suite("Carga por muestras, por ritmo y monotonía")
struct LoadExtrasTests {
    @Test func samplesAtConstantHeartRateMatchTheAverage() throws {
        let start = today.addingTimeInterval(-3600)
        let samples = (0...240).map { HeartRatePoint(date: start.addingTimeInterval(Double($0) * 5), bpm: 150) }
        let bySamples = try #require(BanisterTRIMP.load(samples: samples, restingHeartRate: 50, maxHeartRate: 190, sex: .male))
        let byAverage = try #require(BanisterTRIMP.load(duration: 1200, averageHeartRate: 150, restingHeartRate: 50, maxHeartRate: 190, sex: .male))
        #expect(abs(bySamples - byAverage) < 0.01)
    }

    @Test func intervalsWeighMoreBySamplesThanByAverage() throws {
        // Mitad a 120 y mitad a 180 (media 150): la curva exponencial pesa más lo intenso.
        let start = today.addingTimeInterval(-3600)
        let samples = (0...240).map { HeartRatePoint(date: start.addingTimeInterval(Double($0) * 5), bpm: $0 < 120 ? 120 : 180) }
        let bySamples = try #require(BanisterTRIMP.load(samples: samples, restingHeartRate: 50, maxHeartRate: 190, sex: .male))
        let byAverage = try #require(BanisterTRIMP.load(duration: 1200, averageHeartRate: 150, restingHeartRate: 50, maxHeartRate: 190, sex: .male))
        #expect(bySamples > byAverage)
        // Sensor callado: no se extrapola.
        #expect(BanisterTRIMP.load(samples: Array(samples.prefix(5)), restingHeartRate: 50, maxHeartRate: 190, sex: nil) == nil)
    }

    @Test func paceLoadUsesThresholdRatio() throws {
        let atThreshold = try #require(BanisterTRIMP.load(duration: 3600, pace: 270, thresholdPace: 270, sex: .male))
        let easy = try #require(BanisterTRIMP.load(duration: 3600, pace: 360, thresholdPace: 270, sex: .male))
        #expect(abs(atThreshold - 60 * 0.85 * exp(1.92 * 0.85)) < 0.01)
        #expect(easy < atThreshold)
    }

    @Test func calculatorPrefersSamplesThenAverageThenPace() {
        let base = today.addingTimeInterval(-86_400)
        func run(_ hr: Double?) -> WorkoutSummary {
            WorkoutSummary(activity: .outdoorRun, start: base, duration: 1800, distanceMeters: 6000, averageHeartRate: hr, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        }
        let sampled = run(150), averaged = run(150), paced = run(nil)
        let samples = (0...100).map { HeartRatePoint(date: base.addingTimeInterval(Double($0) * 5), bpm: 150) }
        let inputs = HeartRateLoadInputs(restingHeartRate: 50, maxHeartRate: [.running: 190], sex: nil)
        let result = TrainingLoadCalculator.heartRateLoads([sampled, averaged, paced], inputs: inputs, samples: [sampled.id: samples], thresholdPace: 270)
        #expect(result.skipped == 0)
        #expect(result.loads.map(\.source) == [.heartRateSamples, .averageHeartRate, .pace])
        #expect(result.loads[2].isApproximate)
        let noPace = TrainingLoadCalculator.heartRateLoads([paced], inputs: inputs)
        #expect(noPace.skipped == 1)
    }

    @Test func fosterMonotonyAndStrain() throws {
        func load(_ daysAgo: Int, _ value: Double) -> WorkoutLoad {
            WorkoutLoad(workoutID: UUID(), date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, sport: .running, value: value)
        }
        // 100 cada día salvo uno de descanso: muy monótono.
        let flat = (0..<6).map { load($0, 100) }
        let flatResult = try #require(TrainingMonotony.compute(loads: flat, endingOn: today, calendar: calendar))
        #expect(flatResult.monotony > TrainingMonotony.highMonotony)
        // Días duros y suaves alternados: menos monótono.
        let varied = [load(0, 200), load(2, 40), load(4, 200), load(6, 40)]
        let variedResult = try #require(TrainingMonotony.compute(loads: varied, endingOn: today, calendar: calendar))
        #expect(variedResult.monotony < 1)
        #expect(abs(variedResult.strain - variedResult.weeklyLoad * variedResult.monotony) < 0.001)
        #expect(TrainingMonotony.compute(loads: [load(1, 100)], endingOn: today, calendar: calendar) == nil)
    }
}
