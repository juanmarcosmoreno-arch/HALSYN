import Foundation
import Testing
@testable import HalsynCore

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// Recta hacia el norte a velocidad constante, un punto por segundo.
private func straightRun(seconds: Int, speed: Double, pauseAt: Int? = nil, pause: TimeInterval = 0) -> [LocationSample] {
    (0...seconds).map { second in
        let shift = pauseAt.map { second >= $0 ? pause : 0 } ?? 0
        return LocationSample(latitude: 59.3 + Double(second) * speed / 111_195, longitude: 18.0, altitude: 10, horizontalAccuracy: 4, verticalAccuracy: 3, timestamp: start.addingTimeInterval(Double(second) + shift))
    }
}

private func pulse(seconds: Int, _ bpm: (Int) -> Double) -> [HeartRatePoint] {
    stride(from: 0, through: seconds, by: 5).map { HeartRatePoint(date: start.addingTimeInterval(Double($0)), bpm: bpm($0)) }
}

private func run(km: Double, minutes: Double, hr: Double?, daysAgo: Int = 0) -> WorkoutSummary {
    WorkoutSummary(activity: .outdoorRun, start: start.addingTimeInterval(Double(-daysAgo) * 86_400), duration: minutes * 60, distanceMeters: km * 1000, averageHeartRate: hr, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("SPRING · análisis de carrera")
struct RunAnalyzerTests {
    @Test func steadyRunHasNoDecoupling() throws {
        let insights = try #require(RunAnalyzer.analyze(route: straightRun(seconds: 2400, speed: 3), heartRate: pulse(seconds: 2400) { _ in 150 }))
        #expect(abs(insights.distance - 7200) < 30)
        #expect(insights.movingTime == 2400)
        #expect(insights.warmup == 360)
        #expect(abs(try #require(insights.decoupling)) < 0.5)
        #expect(abs(try #require(insights.halfPaceDifference)) < 2)
        // 3 m/s = 180 m/min a 150 lpm → 1,2 m por latido.
        #expect(abs(try #require(insights.metersPerBeat) - 1.2) < 0.02)
        #expect(insights.segments.count == 36)
        #expect(insights.segments.allSatisfy { $0.heartRate == 150 })
    }

    @Test func pulseRisingAtSamePaceIsPositiveDecoupling() throws {
        // Calentamiento 360 s; mitades de 1020 s. La FC pasa de 140 a 150 en la segunda mitad.
        let insights = try #require(RunAnalyzer.analyze(route: straightRun(seconds: 2400, speed: 3), heartRate: pulse(seconds: 2400) { $0 < 1380 ? 140 : 150 }))
        let decoupling = try #require(insights.decoupling)
        #expect(decoupling > 5.5 && decoupling < 7.5)
    }

    @Test func shortRunHasNoDecoupling() throws {
        let insights = try #require(RunAnalyzer.analyze(route: straightRun(seconds: 900, speed: 3), heartRate: pulse(seconds: 900) { _ in 150 }))
        #expect(insights.decoupling == nil)
        #expect(insights.metersPerBeat != nil)
    }

    @Test func pausesAreNotMovingTime() throws {
        let insights = try #require(RunAnalyzer.analyze(route: straightRun(seconds: 1200, speed: 3, pauseAt: 600, pause: 120), heartRate: []))
        #expect(insights.movingTime == 1199) // el segundo del hueco no cuenta
        #expect(insights.metersPerBeat == nil)
    }

    @Test func noRouteNoAnalysis() {
        #expect(RunAnalyzer.analyze(route: [], heartRate: []) == nil)
    }

    @Test func comparesWithSimilarRuns() throws {
        let current = run(km: 10, minutes: 50, hr: 150)
        let history = [run(km: 10.5, minutes: 55, hr: 152, daysAgo: 3), run(km: 9.5, minutes: 50, hr: 148, daysAgo: 5), run(km: 10, minutes: 52, hr: 155, daysAgo: 8), run(km: 21, minutes: 120, hr: 150, daysAgo: 10), current]
        let comparison = try #require(RunAnalyzer.compare(current, with: history))
        #expect(comparison.count == 3)
        #expect(comparison.paceRank == 1)
        #expect(comparison.efficiencyRank == 1)
        #expect(comparison.efficiencyCount == 4)
        #expect(comparison.paceDifference < 0)
    }

    @Test func needsThreeSimilarRuns() {
        let current = run(km: 10, minutes: 50, hr: 150)
        #expect(RunAnalyzer.compare(current, with: [run(km: 10, minutes: 52, hr: nil, daysAgo: 2), run(km: 5, minutes: 25, hr: nil, daysAgo: 4)]) == nil)
    }
}

@Suite("SPRING · predicción de carrera")
struct RacePredictorTests {
    @Test func riegelFormula() {
        // 5 km en 25:00 → 10 km ≈ 52:07.
        let tenK = RacePredictor.riegel(time: 1500, from: 5000, to: 10000)
        #expect(abs(tenK - 3127) < 2)
    }

    @Test func usesBestRecentEfforts() throws {
        let calendar = Calendar(identifier: .gregorian)
        let runs = [run(km: 5, minutes: 25, hr: nil, daysAgo: 3), run(km: 10, minutes: 55, hr: nil, daysAgo: 6), run(km: 8, minutes: 44, hr: nil, daysAgo: 9),
                    run(km: 12, minutes: 70, hr: nil, daysAgo: 12), run(km: 2, minutes: 8, hr: nil, daysAgo: 2), run(km: 10, minutes: 40, hr: nil, daysAgo: 120)]
        let predictions = RacePredictor.predictions(from: runs, endingOn: start, calendar: calendar)
        #expect(predictions.count == 4)
        let tenK = try #require(predictions.first { $0.distance == .tenK })
        // La de 2 km (corta) y la de hace 120 días no cuentan: 4 carreras.
        #expect(tenK.basedOn == 4)
        #expect(tenK.fastest < tenK.time && tenK.time < tenK.slowest)
        #expect(!tenK.isLongExtrapolation)
        #expect(try #require(predictions.first { $0.distance == .marathon }).isLongExtrapolation)
    }

    @Test func needsThreeRuns() {
        let runs = [run(km: 5, minutes: 25, hr: nil, daysAgo: 3), run(km: 10, minutes: 55, hr: nil, daysAgo: 6)]
        #expect(RacePredictor.predictions(from: runs, endingOn: start, calendar: Calendar(identifier: .gregorian)).isEmpty)
    }
}
