import Foundation
import Testing
@testable import HalsynCore

@Suite("Récords personales de carrera")
struct RunRecordsTests {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func entry(_ day: Int, splits: [TimeInterval], indoor: Bool = false) -> RunRecordEntry {
        RunRecords.entry(id: UUID(), date: base.addingTimeInterval(Double(day) * 86_400), distance: Double(splits.count) * 1000 + 300, duration: splits.reduce(0, +) + 90, kilometerSplits: splits, usesGPS: !indoor)
    }

    @Test func bestEffortsUseConsecutiveFullKilometers() {
        let run = entry(0, splits: [330, 320, 300, 310, 315, 340])
        #expect(run.values[.fastestKilometer] == 300)
        // Mejor bloque de 5 km seguidos: 320+300+310+315+340 = 1585 frente a 1575 (los 5 primeros).
        #expect(run.values[.fastest5K] == 1575)
        #expect(run.values[.fastest10K] == nil)
        #expect(run.values[.longestDistance] == 6300)
    }

    @Test func treadmillAndGPSJumpsDoNotSetSpeedRecords() {
        let treadmill = entry(0, splits: [280, 280, 280, 280, 280], indoor: true)
        #expect(treadmill.values[.fastestKilometer] == nil)
        #expect(treadmill.values[.longestDistance] != nil)
        let glitch = entry(0, splits: [330, 90, 330, 330, 330])
        #expect(glitch.values[.fastestKilometer] == nil)
    }

    @Test func podiumOnlyWhenItMeansSomething() {
        let first = entry(0, splits: [330, 330, 330, 330, 330])
        // La primera carrera no es un récord: no hay con qué compararla.
        #expect(RunRecords.placements(of: first, among: [first]).isEmpty)
        let second = entry(1, splits: [320, 320, 320, 320, 320])
        let placements = RunRecords.placements(of: second, among: [first, second])
        #expect(placements.first { $0.category == .fastest5K }?.rank == 1)
        #expect(placements.first { $0.category == .fastest5K }?.previousBest == 1650)
        // Más lenta que la única anterior: 2.º de 2 no se marca.
        let slower = entry(2, splits: [340, 340, 340, 340, 340])
        #expect(RunRecords.placements(of: slower, among: [first, slower]).first { $0.category == .fastest5K } == nil)
        // Con tres anteriores, ser 2.º o 3.º sí.
        let third = entry(3, splits: [325, 325, 325, 325, 325])
        let history = [first, second, slower, third]
        #expect(RunRecords.placements(of: third, among: history).first { $0.category == .fastest5K }?.rank == 2)
    }

    @Test func boardMatchesFullHistoryAndUpdatesOnTheWatch() {
        let runs = [entry(0, splits: [330, 330, 330]), entry(1, splits: [310, 320, 330]), entry(2, splits: [350, 350, 350]), entry(3, splits: [300, 340, 340])]
        var board = RunRecords.board(Array(runs.prefix(3)))
        #expect(board.top[.fastestKilometer]?.map(\.value) == [310, 330, 350])
        #expect(board.counts[.fastestKilometer] == 3)
        let new = runs[3]
        let fromBoard = board.placements(for: new)
        let fromHistory = RunRecords.placements(of: new, among: runs)
        #expect(fromBoard == fromHistory)
        #expect(fromBoard.first { $0.category == .fastestKilometer }?.rank == 1)
        board.add(new)
        #expect(board.top[.fastestKilometer]?.first?.value == 300)
        #expect(board.top[.fastestKilometer]?.count == 3)
        #expect(board.counts[.fastestKilometer] == 4)
        let data = try? JSONEncoder().encode(board)
        #expect(data.flatMap { try? JSONDecoder().decode(RunRecordBoard.self, from: $0) } == board)
    }

    @Test func lapTrackerSplitsFeedTheEfforts() {
        var tracker = LapTracker(autoLapDistance: 1000)
        for second in stride(from: 0.0, through: 1300, by: 1) {
            tracker.update(distance: second * 1000 / 325, elapsed: second)
        }
        let durations = RunRecords.kilometerDurations(tracker.laps)
        #expect(durations.count == 4)
        #expect(abs((durations.first ?? 0) - 325) < 0.01)
    }
}
