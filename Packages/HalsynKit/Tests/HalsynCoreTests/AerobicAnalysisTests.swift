import Foundation
import Testing
@testable import HalsynCore

@Suite("Capacidad aeróbica: ritmo a pulso fijo, eficiencia y desacople")
struct AerobicAnalysisTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    private let today = Date(timeIntervalSince1970: 1_790_000_000)

    /// Carrera sintética en línea recta: velocidad (m/min) y pulso por segundo.
    private func run(daysAgo: Int, minutes: Int, speed: @escaping (Int) -> Double, heartRate: @escaping (Int) -> Double) -> AerobicRunObservation? {
        let start = today.addingTimeInterval(Double(-daysAgo) * 86_400)
        var route: [LocationSample] = []
        var pulse: [HeartRatePoint] = []
        var meters = 0.0
        for second in 0...(minutes * 60) {
            let date = start.addingTimeInterval(Double(second))
            route.append(LocationSample(latitude: 59.3 + meters / 111_320, longitude: 18.0, altitude: 20, horizontalAccuracy: 4, verticalAccuracy: 3, timestamp: date))
            if second % 5 == 0 { pulse.append(HeartRatePoint(date: date, bpm: heartRate(second))) }
            meters += speed(second) / 60
        }
        return AerobicAnalysis.observe(id: UUID(), date: start, route: route, heartRate: pulse)
    }

    @Test func steadyRunGivesEfficiencyAndOneBin() throws {
        let observation = try #require(run(daysAgo: 1, minutes: 30, speed: { _ in 180 }, heartRate: { _ in 150 }))
        #expect(observation.bins.count == 1)
        let bin = try #require(observation.bins.first)
        #expect(bin.heartRate == 150)
        #expect(abs(bin.speed - 180) < 4)
        #expect(abs((observation.efficiency ?? 0) - 1.2) < 0.03)
        // El calentamiento (15 %, 4,5 min) no cuenta.
        #expect(observation.steadySeconds < 30 * 60 * 0.86)
    }

    @Test func intervalsHaveFewSteadySegments() throws {
        let intervals = try #require(run(daysAgo: 1, minutes: 30, speed: { ($0 / 90) % 2 == 0 ? 240 : 140 }, heartRate: { ($0 / 90) % 2 == 0 ? 170 : 145 }))
        let steady = try #require(run(daysAgo: 1, minutes: 30, speed: { _ in 180 }, heartRate: { _ in 150 }))
        #expect(intervals.steadySeconds < steady.steadySeconds * 0.6)
        #expect(intervals.decoupling == nil)
    }

    @Test func paceAtFixedHeartRateInterpolatesOnly() throws {
        let runs = [
            run(daysAgo: 3, minutes: 25, speed: { _ in 160 }, heartRate: { _ in 140 }),
            run(daysAgo: 6, minutes: 25, speed: { _ in 180 }, heartRate: { _ in 150 }),
            run(daysAgo: 9, minutes: 25, speed: { _ in 200 }, heartRate: { _ in 160 }),
        ].compactMap { $0 }
        #expect(runs.count == 3)
        let start = today.addingTimeInterval(-28 * 86_400)
        let estimate = try AerobicAnalysis.paceAt(150, observations: runs, from: start, to: today).get()
        // 180 m/min = 5:33 /km.
        #expect(abs(estimate.pace - 333) < 8)
        #expect(estimate.fastest <= estimate.pace && estimate.slowest >= estimate.pace)
        #expect(estimate.runs == 3)
        // 175 lpm no se observó: no se extrapola.
        guard case let .failure(error) = AerobicAnalysis.paceAt(175, observations: runs, from: start, to: today) else {
            Issue.record("Debía fallar fuera del rango")
            return
        }
        #expect(error.reason == .outsideObservedRange)
    }

    @Test func notEnoughRunsIsSaid() {
        let runs = [run(daysAgo: 2, minutes: 25, speed: { _ in 180 }, heartRate: { _ in 150 })].compactMap { $0 }
        guard case let .failure(error) = AerobicAnalysis.paceAt(150, observations: runs, from: today.addingTimeInterval(-28 * 86_400), to: today) else {
            Issue.record("Con una carrera no se estima")
            return
        }
        #expect(error.reason == .notEnoughRuns)
    }

    @Test func fasterAtSameHeartRateIsATrend() throws {
        func block(daysAgo: [Int], speed: Double) -> [AerobicRunObservation] {
            daysAgo.enumerated().compactMap { index, days in
                let wobble = Double(index % 3) * 2
                return run(daysAgo: days, minutes: 25, speed: { _ in speed + wobble }, heartRate: { _ in 150 + Double(index % 2) * 5 })
            }
        }
        let previous = block(daysAgo: [60, 64, 68, 72], speed: 165)
        let current = block(daysAgo: [2, 6, 10, 14], speed: 185)
        let trend = try AerobicAnalysis.trend(at: 150, observations: previous + current, today: today, calendar: calendar).get()
        #expect(trend.verdict == .faster)
        #expect((trend.change ?? 0) > 20)
        // Sin período anterior: tendencia sin veredicto.
        let alone = try AerobicAnalysis.trend(at: 150, observations: current, today: today, calendar: calendar).get()
        #expect(alone.verdict == nil)
    }

    @Test func decouplingNeedsLongRegularRuns() throws {
        let drifting = try #require(run(daysAgo: 1, minutes: 45, speed: { _ in 180 }, heartRate: { 140 + Double($0) / 2700 * 15 }))
        let value = try #require(drifting.decoupling)
        #expect(value > 2 && value < 10)
        let short = try #require(run(daysAgo: 1, minutes: 22, speed: { _ in 180 }, heartRate: { 140 + Double($0) / 1320 * 15 }))
        #expect(short.decoupling == nil)
        let summary = try #require(AerobicAnalysis.decoupling([drifting, short], today: today, calendar: calendar))
        #expect(summary.runs28 == 1)
    }

    @Test func efficiencyChangeMustExceedNoise() throws {
        let old = [40, 44, 48, 52].compactMap { run(daysAgo: $0, minutes: 25, speed: { _ in 170 }, heartRate: { _ in 150 }) }
        let new = [3, 7, 11, 15].compactMap { run(daysAgo: $0, minutes: 25, speed: { _ in 172 }, heartRate: { _ in 150 }) }
        let summary = try #require(AerobicAnalysis.efficiency(old + new, today: today, calendar: calendar))
        #expect(summary.windows.contains { $0.days == 28 })
        #expect((summary.change28 ?? 0) > 0)
    }
}
