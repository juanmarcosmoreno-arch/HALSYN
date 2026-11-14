import Foundation
import Testing
@testable import HalsynCore

@Suite("Récords personales y mejores esfuerzos")
struct RunRecordsTests {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    /// Línea de tiempo a 1 punto por segundo con la velocidad (m/s) de cada tramo.
    private func timeline(_ blocks: [(seconds: Int, speed: Double)]) -> [EffortPoint] {
        var points = [EffortPoint(time: 0, distance: 0)]
        var time = 0.0, distance = 0.0
        for block in blocks {
            for _ in 0..<block.seconds {
                time += 1
                distance += block.speed
                points.append(EffortPoint(time: time, distance: distance))
            }
        }
        return points
    }

    private func entry(_ day: Int, _ blocks: [(seconds: Int, speed: Double)]) -> RunRecordEntry {
        let points = timeline(blocks)
        return RunRecords.entry(id: UUID(), date: base.addingTimeInterval(Double(day) * 86_400), distance: points.last?.distance ?? 0, duration: points.last?.time ?? 0, timeline: points)
    }

    @Test func bestEffortInsideALongerRun() throws {
        // 10 min a 3 m/s, 1000 m a 4 m/s (250 s), 10 min a 3 m/s.
        let run = entry(0, [(600, 3), (250, 4), (600, 3)])
        let kilometer = try #require(run.values[.fastestKilometer])
        #expect(abs(kilometer - 250) < 0.5)
        #expect(abs((run.starts?[.fastestKilometer] ?? 0) - 600) < 1)
        // 400 m también salen del tramo rápido (100 s).
        #expect(abs((run.values[.best400] ?? 0) - 100) < 0.5)
        // El mejor km no tiene por qué empezar en un kilómetro entero (empieza en 1800 m).
        #expect(run.values[.fastest10K] == nil)
        #expect(run.values[.bestHalf] == nil)
    }

    @Test func pausesCountAsTime() throws {
        // 500 m, 2 min parado, 500 m: el km incluye la pausa.
        let run = entry(0, [(125, 4), (120, 0), (125, 4)])
        let kilometer = try #require(run.values[.fastestKilometer])
        #expect(kilometer > 360)
    }

    @Test func gpsGlitchesAndInconsistentDistanceDoNotMakeRecords() {
        // Un salto de 500 m en 10 s (50 m/s): ese tramo es más rápido que 2:30 /km y se descarta.
        var points = timeline([(300, 3)])
        let jump = points.last!
        points.append(EffortPoint(time: jump.time + 10, distance: jump.distance + 500))
        let glitch = RunRecords.bestEffort(points, distance: 400)
        #expect(glitch.map { 400 / $0.duration <= RunRecords.maximumEffortSpeed } ?? true)
        // GPS 5,4 km frente a 4,9 km de Salud (10 % más): no cuenta para los tiempos.
        let gps = timeline([(1800, 3)])
        let mismatch = RunRecords.entry(id: UUID(), date: base, distance: 4900, duration: 1800, timeline: gps, recordedDistance: 4900)
        #expect(mismatch.values[.fastestKilometer] == nil)
        #expect(mismatch.values[.longestDistance] == 4900)
        let consistent = RunRecords.entry(id: UUID(), date: base, distance: 5400, duration: 1800, timeline: gps, recordedDistance: 5350)
        #expect(consistent.values[.fastestKilometer] != nil)
    }

    @Test func treadmillOnlyHasDistanceAndDuration() {
        let run = RunRecords.entry(id: UUID(), date: base, distance: 6000, duration: 1900, timeline: [])
        #expect(run.values[.fastestKilometer] == nil)
        #expect(run.values[.longestDistance] == 6000)
    }

    @Test func podiumOnlyWhenItMeansSomething() {
        let first = entry(0, [(1700, 3)])
        #expect(RunRecords.placements(of: first, among: [first]).isEmpty)
        let second = entry(1, [(1650, 3.1)])
        let placements = RunRecords.placements(of: second, among: [first, second])
        #expect(placements.first { $0.category == .fastest5K }?.rank == 1)
        let slower = entry(2, [(1800, 2.9)])
        #expect(RunRecords.placements(of: slower, among: [first, slower]).first { $0.category == .fastest5K } == nil)
        let third = entry(3, [(1700, 3.05)])
        #expect(RunRecords.placements(of: third, among: [first, second, slower, third]).first { $0.category == .fastest5K }?.rank == 2)
    }

    @Test func boardMatchesFullHistoryAndUpdatesOnTheWatch() {
        let runs = [entry(0, [(400, 3)]), entry(1, [(400, 3.3)]), entry(2, [(400, 2.8)]), entry(3, [(400, 3.6)])]
        var board = RunRecords.board(Array(runs.prefix(3)))
        #expect(board.counts[.fastestKilometer] == 3)
        let new = runs[3]
        #expect(board.placements(for: new) == RunRecords.placements(of: new, among: runs))
        #expect(board.placements(for: new).first { $0.category == .fastestKilometer }?.rank == 1)
        board.add(new)
        #expect(board.top[.fastestKilometer]?.count == 3)
        let data = try? JSONEncoder().encode(board)
        #expect(data.flatMap { try? JSONDecoder().decode(RunRecordBoard.self, from: $0) } == board)
    }

    @Test func periodBestsAndProgression() {
        let runs = [entry(0, [(400, 3)]), entry(30, [(400, 3.2)]), entry(60, [(400, 3.1)]), entry(90, [(400, 3.4)])]
        let progression = RunRecords.progression(.fastestKilometer, entries: runs)
        // 3.0 → 3.2 → 3.4 m/s (3.1 no fue récord).
        #expect(progression.count == 3)
        #expect(progression.map(\.id) == [runs[0].id, runs[1].id, runs[3].id])
        let recent = RunRecords.bests(runs, from: base.addingTimeInterval(50 * 86_400), to: base.addingTimeInterval(70 * 86_400))
        #expect(recent[.fastestKilometer]?.id == runs[2].id)
    }

    @Test func routeTimelineUsesTheGPSFilter() {
        var route: [LocationSample] = []
        for second in 0...600 {
            route.append(LocationSample(latitude: 59.3 + Double(second) * 3 / 111_320, longitude: 18, horizontalAccuracy: 5, timestamp: base.addingTimeInterval(Double(second))))
        }
        let points = RunRecords.timeline(from: route)
        #expect(abs((points.last?.distance ?? 0) - 1800) < 40)
        #expect(abs((RunRecords.bestEffort(points, distance: 1000)?.duration ?? 0) - 333) < 15)
    }
}
