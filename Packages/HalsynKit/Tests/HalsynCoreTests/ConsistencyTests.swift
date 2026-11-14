import Foundation
import Testing
@testable import HalsynCore

@Suite("Constancia")
struct ConsistencyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()
    /// Jueves 12/11/2026.
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))! }

    /// Carreras martes, jueves y sábado de las últimas `weeks` semanas (más esta).
    private func regularRuns(weeks: Int = 10, perWeek: [Int] = [1, 3, 5], distance: Double = 6000) -> [(date: Date, distance: Double)] {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        var runs: [(date: Date, distance: Double)] = []
        for week in 0...weeks {
            for day in perWeek {
                if let date = calendar.date(byAdding: .day, value: day - 7 * week, to: monday), date <= today {
                    runs.append((date.addingTimeInterval(18 * 3600), distance))
                }
            }
        }
        return runs
    }

    @Test func perfectRegularityScoresHigh() throws {
        let report = ConsistencyEngine.evaluate(runs: regularRuns(), targetPerWeek: 3, planAdherence: 1, today: today, calendar: calendar)
        #expect(try #require(report.score) == 100)
        #expect(report.streakWeeks >= 9)
        #expect(report.interruptions == 0)
        // Sin plan, el peso se reparte y sigue siendo 100.
        let noPlan = ConsistencyEngine.evaluate(runs: regularRuns(), targetPerWeek: 3, today: today, calendar: calendar)
        #expect(noPlan.score == 100)
        #expect(noPlan.parts.count == 3)
        #expect(abs(noPlan.parts.map(\.weight).reduce(0, +) - 1) < 1e-9)
    }

    @Test func illnessWeekIsNotPenalised() throws {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let sickWeek = calendar.date(byAdding: .day, value: -21, to: monday)!
        let sickEnd = calendar.date(byAdding: .day, value: 7, to: sickWeek)!
        let runs = regularRuns().filter { !($0.date >= sickWeek && $0.date < sickEnd) }
        let sickDays = Set((0..<6).compactMap { calendar.date(byAdding: .day, value: $0, to: sickWeek) })
        let excused = ConsistencyEngine.evaluate(runs: runs, targetPerWeek: 3, excusedDays: sickDays, today: today, calendar: calendar)
        let notExcused = ConsistencyEngine.evaluate(runs: runs, targetPerWeek: 3, today: today, calendar: calendar)
        #expect(try #require(excused.score) == 100)
        #expect(try #require(notExcused.score) < 100)
        #expect(excused.weeks.contains { $0.excused })
        // La semana enferma no corta la racha.
        #expect(excused.streakWeeks > 4)
    }

    @Test func plannedLightWeekIsNotPenalised() throws {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let lightWeek = calendar.date(byAdding: .day, value: -14, to: monday)!
        let lightEnd = calendar.date(byAdding: .day, value: 7, to: lightWeek)!
        let runs = regularRuns().filter { !($0.date >= lightWeek && $0.date < lightEnd && calendar.component(.weekday, from: $0.date) != 3) }
        let report = ConsistencyEngine.evaluate(runs: runs, targetPerWeek: 3, lightWeekStarts: [lightWeek], today: today, calendar: calendar)
        let regularity = try #require(report.parts.first { $0.component == .regularity })
        #expect(regularity.value == 1)
        let stability = try #require(report.parts.first { $0.component == .stability })
        #expect(stability.value == 1)
    }

    @Test func gapsAreCounted() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let gapStart = calendar.date(byAdding: .day, value: -35, to: monday)!
        let gapEnd = calendar.date(byAdding: .day, value: -21, to: monday)!
        let runs = regularRuns().filter { !($0.date >= gapStart && $0.date < gapEnd) }
        let report = ConsistencyEngine.evaluate(runs: runs, targetPerWeek: 3, today: today, calendar: calendar)
        #expect(report.interruptions == 1)
        #expect(report.longestGapDays >= 14)
        #expect(report.streakWeeks < 5)
    }

    @Test func shortHistoryHasNoScore() {
        let report = ConsistencyEngine.evaluate(runs: regularRuns(weeks: 2), targetPerWeek: 3, today: today, calendar: calendar)
        #expect(report.score == nil)
    }
}
