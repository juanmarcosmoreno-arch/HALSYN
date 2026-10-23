import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2 // lunes
    return calendar
}()

/// Miércoles 15 de julio de 2026, 12:00.
private let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))!

private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
}

private func series(_ kind: MetricKind, _ values: [Int: Double]) -> MetricSeries {
    MetricSeries(kind: kind, values: values.map { DailyValue(day: day($0.key), value: $0.value) }.sorted { $0.day < $1.day }, origin: .demo)
}

private func run(_ offset: Int, km: Double) -> WorkoutSummary {
    WorkoutSummary(activity: .outdoorRun, start: day(offset).addingTimeInterval(7 * 3600), duration: km * 330, distanceMeters: km * 1000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("MÅL · objetivos")
struct GoalTests {
    private let evaluator = GoalEvaluator(calendar: calendar)

    @Test func weeklySumAndPace() {
        // Semana del lunes 13 al domingo 19: lunes y martes hechos, miércoles a mediodía.
        let goal = GoalDefinition(kind: .exerciseMinutes, period: .weekly, target: 150)
        let data = GoalData(series: [series(.exerciseTime, [-2: 40, -1: 40, 0: 10, -3: 300])], runs: [], calendar: calendar)
        let progress = evaluator.progress(goal, data: data, now: now)
        #expect(progress.current == 90)
        // Pasado ≈ 2,5/7 de la semana → esperado ≈ 54 min: va por delante.
        #expect(progress.pace == .ahead)
        #expect(progress.remaining == 60)
        // Quedan 5 días (miércoles incluido).
        #expect(progress.neededPerRemainingDay == 12)
    }

    @Test func dailyGoalCompletesAndBehind() {
        let goal = GoalDefinition(kind: .steps, period: .daily, target: 8000)
        let done = GoalData(series: [series(.steps, [0: 9000])], runs: [], calendar: calendar)
        #expect(evaluator.progress(goal, data: done, now: now).pace == .completed)
        let behind = GoalData(series: [series(.steps, [0: 2000])], runs: [], calendar: calendar)
        #expect(evaluator.progress(goal, data: behind, now: now).pace == .behind)
    }

    @Test func runsAndRunningDistanceFromWorkouts() {
        let data = GoalData(series: [], runs: [run(-2, km: 8), run(0, km: 5), run(-3, km: 12)], calendar: calendar)
        let count = evaluator.progress(GoalDefinition(kind: .runs, period: .weekly, target: 3), data: data, now: now)
        #expect(count.current == 2)
        let distance = evaluator.progress(GoalDefinition(kind: .runningDistance, period: .weekly, target: 20_000), data: data, now: now)
        #expect(distance.current == 13_000)
    }

    @Test func sleepIsAnAverageNotASum() {
        let goal = GoalDefinition(kind: .sleepAverage, period: .weekly, target: 7)
        let data = GoalData(series: [series(.sleepDuration, [-2: 6.5, -1: 7.5, 0: 8])], runs: [], calendar: calendar)
        let progress = evaluator.progress(goal, data: data, now: now)
        #expect(abs(progress.current - 7.333) < 0.01)
        #expect(progress.isCompleted)
        #expect(progress.neededPerRemainingDay == nil)
        let empty = evaluator.progress(goal, data: GoalData(series: [], runs: [], calendar: calendar), now: now)
        #expect(empty.pace == .noData)
    }

    @Test func historyAndStreak() {
        let goal = GoalDefinition(kind: .steps, period: .daily, target: 8000)
        // Cumplido hoy y los 3 días anteriores; hace 4 días no.
        let data = GoalData(series: [series(.steps, [0: 8500, -1: 9000, -2: 8000, -3: 12000, -4: 3000, -5: 9000])], runs: [], calendar: calendar)
        #expect(evaluator.streak(goal, data: data, now: now) == 4)
        let history = evaluator.history(goal, data: data, now: now, count: 5)
        #expect(history.map(\.isCompleted) == [true, false, true, true, true])
        #expect(history.last?.interval.start == day(-1))
    }

    @Test func unfinishedTodayDoesNotBreakStreak() {
        let goal = GoalDefinition(kind: .steps, period: .daily, target: 8000)
        let data = GoalData(series: [series(.steps, [0: 1000, -1: 9000, -2: 9000])], runs: [], calendar: calendar)
        #expect(evaluator.streak(goal, data: data, now: now) == 2)
    }

    @Test func progressionGrowsTenPercentPerWeekUpToTheEnd() {
        let progression = GoalProgression(startValue: 10_000, endValue: 20_000, startDate: day(-14))
        #expect(progression.target(week: 0) == 10_000)
        #expect(abs(progression.target(week: 1) - 11_000) < 0.001)
        #expect(abs(progression.target(week: 2) - 12_100) < 0.001)
        #expect(progression.target(week: 20) == 20_000)
        #expect(progression.weeksToReachEnd == 8)
        let goal = GoalDefinition(kind: .runningDistance, period: .weekly, target: 20_000, progression: progression)
        #expect(abs(goal.target(on: now, calendar: calendar) - 12_100) < 0.001)
    }

    @Test func progressionOnlyForWeeklyRunningDistance() {
        let progression = GoalProgression(startValue: 10, endValue: 20, startDate: now)
        #expect(GoalDefinition(kind: .steps, period: .weekly, target: 1, progression: progression).progression == nil)
    }

    @Test func invalidPeriodFallsBackToAllowed() {
        #expect(GoalDefinition(kind: .runs, period: .daily, target: 1).period == .weekly)
    }

    @Test func storageRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "goals-\(UUID().uuidString)"))
        let goals = [
            GoalDefinition(kind: .steps, period: .daily, target: 9000, reminder: GoalReminder(weekdays: [2, 4], minutes: 19 * 60), createdAt: day(0)),
            GoalDefinition(kind: .runningDistance, period: .weekly, target: 30_000, progression: GoalProgression(startValue: 15_000, endValue: 30_000, startDate: day(-7)), createdAt: day(0)),
        ]
        GoalStorage.save(goals, to: defaults)
        #expect(GoalStorage.load(from: defaults) == goals)
        defaults.set(Data("x".utf8), forKey: GoalStorage.key)
        #expect(GoalStorage.load(from: defaults).isEmpty)
    }

    @Test func demoDataFeedsGoals() async {
        let provider = DemoHealthDataProvider(calendar: calendar, now: { now })
        let goals = GoalDefinition.templates
        let data = await provider.goalData(for: goals, endingOn: now, calendar: calendar)
        for goal in goals {
            let progress = evaluator.progress(goal, data: data, now: now)
            #expect(progress.target > 0)
            #expect(progress.current >= 0)
        }
        #expect(!data.runs.isEmpty)
    }
}

@Suite("Widgets · resumen compartido")
struct WidgetSnapshotTests {
    @Test func groupIdentifierFromAnyTarget() {
        #expect(WidgetSnapshotStore.groupIdentifier(bundleIdentifier: "com.juanmarcos.halsyn") == "group.com.juanmarcos.halsyn")
        #expect(WidgetSnapshotStore.groupIdentifier(bundleIdentifier: "com.juanmarcos.halsyn.widgets") == "group.com.juanmarcos.halsyn")
        #expect(WidgetSnapshotStore.groupIdentifier(bundleIdentifier: "com.juanmarcos.halsyn.watchkitapp") == "group.com.juanmarcos.halsyn")
        #expect(WidgetSnapshotStore.groupIdentifier(bundleIdentifier: "com.juanmarcos.halsyn.watchkitapp.widgets") == "group.com.juanmarcos.halsyn")
    }

    @Test func roundTripAndClamping() throws {
        let defaults = try #require(UserDefaults(suiteName: "widget-\(UUID().uuidString)"))
        let snapshot = WidgetSnapshot(updatedAt: now, score: 140, recovery: -5, steps: 9000, goal: .init(title: "x", fraction: 1.4, isCompleted: true), isDemo: false)
        #expect(snapshot.score == 100 && snapshot.recovery == 0 && snapshot.goal?.fraction == 1)
        WidgetSnapshotStore.save(snapshot, to: defaults)
        #expect(WidgetSnapshotStore.load(from: defaults) == snapshot)
    }

    @Test func staleness() {
        let snapshot = WidgetSnapshot(updatedAt: now, isDemo: false)
        #expect(!snapshot.isStale(at: now.addingTimeInterval(3600)))
        #expect(snapshot.isStale(at: now.addingTimeInterval(7 * 3600)))
        #expect(snapshot.isFromToday(now.addingTimeInterval(3600), calendar: calendar))
        #expect(!snapshot.isFromToday(now.addingTimeInterval(13 * 3600), calendar: calendar))
    }
}
