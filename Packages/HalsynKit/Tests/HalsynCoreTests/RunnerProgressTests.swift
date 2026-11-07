import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
private let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 20))!
private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: today))!.addingTimeInterval(8 * 3600) }

private func run(_ days: Int, km: Double, pace: Double, hr: Double?) -> WorkoutSummary {
    WorkoutSummary(activity: .outdoorRun, start: daysAgo(days), duration: km * pace, distanceMeters: km * 1000, averageHeartRate: hr, maxHeartRate: 186, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("Evolución del corredor")
struct RunnerProgressTests {
    @Test func modelPointsOnlySeeThePast() {
        // Un test de hace 2 semanas: los puntos anteriores no lo ven.
        let result = PerformanceResult(date: daysAgo(14), distance: 5000, time: 1320, kind: .test)
        let progress = RunnerProgress.build(runs: [], results: [result], maxHeartRate: 186, weeks: 8, today: today, calendar: calendar)
        #expect(progress.modelPoints.allSatisfy { $0.date >= calendar.startOfDay(for: daysAgo(14)) })
        #expect(progress.modelPoints.count == 3)
        #expect(abs((progress.modelPoints.last?.fiveK ?? 0) - 1320) < 1)
    }

    @Test func weeksSplitIntensity() throws {
        let runs = [run(1, km: 10, pace: 330, hr: 140), run(2, km: 6, pace: 270, hr: 172), run(3, km: 8, pace: 320, hr: 158)]
        let progress = RunnerProgress.build(runs: runs, results: [], maxHeartRate: 186, weeks: 4, today: today, calendar: calendar)
        let total = progress.weeks.map(\.distance).reduce(0, +)
        #expect(abs(total - 24_000) < 0.1)
        let perWeek: [Double] = progress.weeks.map { week in week.easyMinutes + week.moderateMinutes + week.hardMinutes }
        let minutes: Double = perWeek.reduce(0, +)
        // 10 km a 5:30 + 6 km a 4:30 + 8 km a 5:20 = 7480 s.
        let expected: Double = 7480.0 / 60.0
        #expect(abs(minutes - expected) < 0.01)
        #expect(progress.weeks.map(\.hardMinutes).reduce(0, +) == 27)
    }

    @Test func bestEffortsComeFromRunsNearTheDistance() throws {
        let runs = [run(10, km: 5.1, pace: 300, hr: 170), run(20, km: 5.0, pace: 290, hr: 175), run(30, km: 8, pace: 280, hr: 160)]
        let progress = RunnerProgress.build(runs: runs, results: [], maxHeartRate: 186, weeks: 4, today: today, calendar: calendar)
        let fiveK = try #require(progress.bestEfforts.first { $0.distance == .fiveK })
        #expect(abs(fiveK.time - 1450) < 1)
        #expect(progress.bestEfforts.first { $0.distance == .tenK } == nil)
    }

    @Test func heartRateAtComparablePace() throws {
        // FC = 300 − 0,5 × ritmo: a 320 s/km da 140.
        let runs = [300.0, 310, 320, 330, 340].enumerated().map { index, pace in
            run(index + 1, km: 6, pace: pace, hr: 300 - 0.5 * pace)
        }
        #expect(abs(try #require(RunnerProgress.heartRate(at: 320, runs: runs)) - 140) < 0.01)
        // Fuera del rango observado no se extrapola.
        #expect(RunnerProgress.heartRate(at: 400, runs: runs) == nil)
        #expect(RunnerProgress.heartRate(at: 320, runs: Array(runs.prefix(3))) == nil)
    }
}

@Suite("Explicaciones por reglas")
struct CoachInsightsTests {
    private func progress(weeks: [RunnerProgress.Week], points: [RunnerProgress.ModelPoint] = []) -> RunnerProgress {
        RunnerProgress(modelPoints: points, weeks: weeks, bestEfforts: [], referencePace: nil, comparableHeartRate: [])
    }

    private func week(_ index: Int, km: Double, runs: Int = 3, easy: Double = 100, hard: Double = 20) -> RunnerProgress.Week {
        RunnerProgress.Week(start: daysAgo(7 * (8 - index)), distance: km * 1000, minutes: easy + hard, runs: runs, easyMinutes: easy, moderateMinutes: 0, hardMinutes: hard, unknownMinutes: 0)
    }

    @Test func volumeJumpAndConsistency() {
        let weeks = (0..<4).map { week($0, km: 20) } + (4..<8).map { week($0, km: 30) }
        let insights = CoachInsights.generate(progress: progress(weeks: weeks), performance: nil, restingHeartRate: [], recovery: [], today: today, calendar: calendar)
        #expect(insights.contains(.volumeChanged(ratio: 1.5, weekly: 30_000)))
        #expect(insights.contains(.consistent(runsPerWeek: 3, weeks: 4)))
        // Lo que pide atención va primero.
        #expect(insights.first?.tone == .caution)
    }

    @Test func tooMuchIntensityNeedsEnoughMinutes() {
        let heavy = (0..<8).map { week($0, km: 25, easy: 60, hard: 60) }
        #expect(CoachInsights.generate(progress: progress(weeks: heavy), performance: nil, restingHeartRate: [], recovery: [], today: today, calendar: calendar).contains { if case .tooMuchIntensity = $0 { return true }; return false })
        let balanced = (0..<8).map { week($0, km: 25, easy: 160, hard: 30) }
        #expect(!CoachInsights.generate(progress: progress(weeks: balanced), performance: nil, restingHeartRate: [], recovery: [], today: today, calendar: calendar).contains { if case .tooMuchIntensity = $0 { return true }; return false })
    }

    @Test func fiveKChangeNeedsTenSeconds() {
        let weeks = (0..<8).map { week($0, km: 25) }
        let points = [RunnerProgress.ModelPoint(date: daysAgo(28), vdot: 45, fiveK: 1300), RunnerProgress.ModelPoint(date: daysAgo(0), vdot: 46, fiveK: 1265)]
        let insights = CoachInsights.generate(progress: progress(weeks: weeks, points: points), performance: nil, restingHeartRate: [], recovery: [], today: today, calendar: calendar)
        #expect(insights.contains(.fiveKChanged(seconds: -35, weeks: 4)))
        let small = [RunnerProgress.ModelPoint(date: daysAgo(28), vdot: 45, fiveK: 1300), RunnerProgress.ModelPoint(date: daysAgo(0), vdot: 45.1, fiveK: 1295)]
        #expect(!CoachInsights.generate(progress: progress(weeks: weeks, points: small), performance: nil, restingHeartRate: [], recovery: [], today: today, calendar: calendar).contains { if case .fiveKChanged = $0 { return true }; return false })
    }

    @Test func restingHeartRateAboveBaseline() throws {
        let baseline = (3..<33).map { DailyValue(day: daysAgo($0), value: 50 + Double($0 % 3) - 1) }
        let high = baseline + [DailyValue(day: daysAgo(0), value: 57), DailyValue(day: daysAgo(1), value: 56), DailyValue(day: daysAgo(2), value: 56)]
        #expect(try #require(CoachInsights.restingHeartRateDelta(high, today: today, calendar: calendar)) >= 5)
        let normal = baseline + [DailyValue(day: daysAgo(0), value: 51), DailyValue(day: daysAgo(1), value: 50)]
        #expect(CoachInsights.restingHeartRateDelta(normal, today: today, calendar: calendar) == nil)
    }
}
