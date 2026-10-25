import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
/// Viernes 23 de octubre de 2026.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!

private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today)! }

private func run(_ date: Date, km: Double, minutesPerKm: Double) -> WorkoutSummary {
    WorkoutSummary(activity: .outdoorRun, start: date, duration: km * minutesPerKm * 60, distanceMeters: km * 1000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("VDOT (Daniels y Gilbert)")
struct VDOTTests {
    @Test func matchesPublishedTables() throws {
        // Tabla de Daniels, VDOT 50: 5 km 19:57, 10 km 41:21, media 1:31:35, maratón 3:10:49.
        #expect(abs(try #require(VDOT.value(distance: 5000, time: 19 * 60 + 57)) - 50) < 0.15)
        #expect(abs(VDOT.raceTime(vdot: 50, distance: 10_000) - (41 * 60 + 21)) < 15)
        #expect(abs(VDOT.raceTime(vdot: 50, distance: RaceDistance.half.rawValue) - (91 * 60 + 35)) < 40)
        #expect(abs(VDOT.raceTime(vdot: 50, distance: RaceDistance.marathon.rawValue) - (190 * 60 + 49)) < 120)
        // VDOT 40: 5 km 24:08.
        #expect(abs(VDOT.raceTime(vdot: 40, distance: 5000) - (24 * 60 + 8)) < 10)
    }

    @Test func trainingPacesMatchTables() {
        // VDOT 50: umbral 4:15/km y series 3:55/km (± 3 s).
        let paces = TrainingPaces.from(vdot: 50, target: .tenK)
        #expect(abs(paces.tempo.center.secondsPerKilometer - 255) < 3)
        #expect(abs(paces.interval.center.secondsPerKilometer - 235) < 3)
        // Suave más lento que el umbral y con un rango.
        #expect(paces.easy.fastest > paces.tempo.slowest)
        #expect(paces.easy.slowest - paces.easy.fastest > 15)
        // Sin objetivo, ritmo de carrera = previsto (41:21 → 4:08/km).
        #expect(abs(paces.race.secondsPerKilometer - 248) < 2)
        // Con objetivo, el ritmo de carrera es el del objetivo.
        #expect(TrainingPaces.from(vdot: 50, target: .tenK, goalTime: 2400).race.secondsPerKilometer == 240)
    }

    @Test func roundTripAndValidity() throws {
        let time = VDOT.raceTime(vdot: 45, distance: 5000)
        #expect(abs(try #require(VDOT.value(distance: 5000, time: time)) - 45) < 0.01)
        #expect(VDOT.value(distance: 400, time: 60) == nil) // demasiado corto
    }
}

@Suite("Forma actual")
struct FitnessEstimatorTests {
    @Test func freshResultWins() throws {
        let test = PerformanceResult(date: daysAgo(10), distance: 5000, time: 1197, kind: .test)
        let runs = [run(daysAgo(3), km: 10, minutesPerKm: 4.5)] // mejor que el test, pero es un entrenamiento
        let estimate = try #require(FitnessEstimator.estimate(results: [test], runs: runs, today: today, calendar: calendar))
        #expect(estimate.source == .result(test))
        #expect(!estimate.needsTest(today: today, calendar: calendar))
    }

    @Test func trainingRunsAsFallback() throws {
        let runs = [run(daysAgo(3), km: 8, minutesPerKm: 5.5), run(daysAgo(6), km: 5, minutesPerKm: 5.0), run(daysAgo(60), km: 5, minutesPerKm: 4.0)]
        let estimate = try #require(FitnessEstimator.estimate(results: [], runs: runs, today: today, calendar: calendar))
        #expect(estimate.isFromTraining)
        #expect(estimate.needsTest(today: today, calendar: calendar))
        // El de hace 60 días no cuenta: el mejor reciente es 5 km a 5:00/km.
        #expect(abs(estimate.vdot - (VDOT.value(distance: 5000, time: 1500) ?? 0)) < 0.01)
    }

    @Test func olderResultBeatsWeakTraining() throws {
        let race = PerformanceResult(date: daysAgo(70), distance: 10_000, time: 2700, kind: .race)
        let runs = [run(daysAgo(3), km: 8, minutesPerKm: 6)]
        let estimate = try #require(FitnessEstimator.estimate(results: [race], runs: runs, today: today, calendar: calendar))
        #expect(estimate.source == .result(race))
        #expect(estimate.needsTest(today: today, calendar: calendar)) // más de 6 semanas
    }

    @Test func nothingMeansNoEstimate() {
        #expect(FitnessEstimator.estimate(results: [], runs: [], today: today, calendar: calendar) == nil)
    }
}

@Suite("Viabilidad del objetivo")
struct GoalAssessmentTests {
    let estimate = FitnessEstimate(vdot: 45, date: daysAgo(5), source: .result(PerformanceResult(date: daysAgo(5), distance: 5000, time: VDOT.raceTime(vdot: 45, distance: 5000), kind: .test)))

    func assess(goal: TimeInterval?, weeks: Int, distance: RaceDistance = .tenK, weekly: Double = 30_000) -> GoalAssessment {
        let race = calendar.date(byAdding: .day, value: 7 * weeks, to: today)!
        return GoalCoach.assess(goalTime: goal, distance: distance, raceDate: race, estimate: estimate, weeklyDistance: weekly, today: today, calendar: calendar)
    }

    @Test func verdictsFollowTheUsualImprovement() {
        let predicted = VDOT.raceTime(vdot: 45, distance: 10_000)
        // 12 semanas, 1 de afinamiento → 11 de entrenamiento: habitual ≈ +1,8 VDOT.
        #expect(assess(goal: predicted + 60, weeks: 12).verdict == .alreadyThere)
        #expect(assess(goal: VDOT.raceTime(vdot: 46.5, distance: 10_000), weeks: 12).verdict == .realistic)
        #expect(assess(goal: VDOT.raceTime(vdot: 48.5, distance: 10_000), weeks: 12).verdict == .ambitious)
        #expect(assess(goal: VDOT.raceTime(vdot: 52, distance: 10_000), weeks: 12).verdict == .unlikely)
        #expect(assess(goal: nil, weeks: 12).verdict == nil)
    }

    @Test func reachableTimeImprovesWithWeeks() {
        let short = assess(goal: nil, weeks: 6)
        let long = assess(goal: nil, weeks: 18)
        #expect(long.reachableTime < short.reachableTime)
        #expect(short.reachableTime < short.predictedTime)
        #expect(long.trainingWeeks == 17)
    }

    @Test func warnsAboutShortPreparationAndVolume() {
        let marathon = assess(goal: nil, weeks: 10, distance: .marathon, weekly: 15_000)
        #expect(marathon.warnings.contains(.shortPreparation(minimumWeeks: 16)))
        #expect(marathon.warnings.contains(.lowVolume(minimumWeekly: 30_000)))
        #expect(assess(goal: nil, weeks: 10).warnings.isEmpty)
    }
}

@Suite("Plan con objetivo: tests, progreso y reajuste")
struct GoalPlanTests {
    let trainingEstimate = FitnessEstimate(vdot: 44, date: daysAgo(2), source: .training(runs: 5))

    func makePlan(weeks: Int = 14, weekly: Double = 25_000) throws -> TrainingPlan {
        let race = calendar.date(byAdding: .day, value: 7 * weeks + 2, to: today)!
        let goal = PlanGoal(distance: .tenK, raceDate: race, runsPerWeek: 4, goalTime: 48 * 60)
        return try #require(TrainingPlanGenerator.make(goal: goal, estimate: trainingEstimate, weeklyDistance: weekly, today: today, calendar: calendar))
    }

    @Test func schedulesAnInitialTestAndRetests() throws {
        let plan = try makePlan()
        #expect(plan.vdot == 44)
        let tests = plan.weeks.filter { $0.sessions.contains { $0.kind == .test } }.map(\.index)
        // Al empezar (la forma sale de entrenamientos) y a las 6 semanas; el de
        // la semana 12 no, porque queda a menos de 3 semanas de la carrera.
        #expect(tests == [0, 6])
        // Ningún test en las 2 últimas semanas antes de la carrera.
        let last = plan.weeks.count - 1
        #expect(tests.allSatisfy { $0 <= last - 3 })
        let test = try #require(plan.weeks[0].sessions.first { $0.kind == .test })
        #expect(test.repeatDistance == 5000)
        // Al reloj va solo el esfuerzo de 5 km.
        let watch = try #require(PlanAdaptation.intervalPlan(for: test, id: "t", name: "Test"))
        #expect(watch.warmup == nil && watch.cooldown == nil && watch.work == .distance(5000) && watch.repeats == 1)
    }

    @Test func freshTestMeansNoInitialTest() throws {
        let fresh = FitnessEstimate(vdot: 44, date: daysAgo(3), source: .result(PerformanceResult(date: daysAgo(3), distance: 5000, time: 1300, kind: .test)))
        let race = calendar.date(byAdding: .day, value: 7 * 8 + 2, to: today)!
        let plan = try #require(TrainingPlanGenerator.make(goal: PlanGoal(distance: .tenK, raceDate: race, runsPerWeek: 4), estimate: fresh, weeklyDistance: 25_000, today: today, calendar: calendar))
        #expect(!plan.weeks[0].sessions.contains { $0.kind == .test })
    }

    @Test func smallVolumeUsesA3kTest() {
        #expect(TrainingPlanGenerator.testDistance(weeklyDistance: 10_000) == 3000)
        #expect(TrainingPlanGenerator.testDistance(weeklyDistance: 20_000) == 5000)
    }

    @Test func detectsTheTestWorkout() throws {
        let session = PlannedSession(date: today, kind: .test, distance: 8000, repeats: 1, repeatDistance: 5000)
        let runs = [run(today.addingTimeInterval(3600), km: 5.05, minutesPerKm: 4.8), run(today.addingTimeInterval(7200), km: 9, minutesPerKm: 6)]
        let found = try #require(GoalCoach.testCandidate(for: session, runs: runs, calendar: calendar))
        #expect(found.distanceMeters == 5050)
    }

    @Test func progressComparesPlannedAndDone() throws {
        let plan = try makePlan()
        // Dos semanas después, habiendo corrido la mitad de lo planeado.
        let later = calendar.date(byAdding: .day, value: 17, to: today)!
        let planned = plan.weeks[0].distance + plan.weeks[1].distance
        let runs = [run(plan.weeks[0].start.addingTimeInterval(3600 * 30), km: planned / 4000, minutesPerKm: 5.5)]
        let progress = PlanProgress.evaluate(plan: plan, runs: runs, estimate: trainingEstimate, today: later, calendar: calendar)
        #expect(progress.weeksEvaluated == 2)
        #expect(progress.status == .behind)
        #expect(abs((progress.adherence ?? 0) - 0.25) < 0.01)
        #expect(PlanProgress.evaluate(plan: plan, runs: [], estimate: nil, today: today, calendar: calendar).status == .notStarted)
    }

    @Test func replanLowersVolumeWhenBehindAndKeepsThePast() throws {
        let plan = try makePlan()
        let later = calendar.date(byAdding: .day, value: 17, to: today)! // 3.ª semana
        #expect(TrainingPlanGenerator.needsWeeklyReplan(plan, today: later, calendar: calendar))
        let current = try #require(plan.week(containing: later, calendar: calendar))
        let runs = [run(plan.weeks[0].start.addingTimeInterval(3600 * 30), km: 10, minutesPerKm: 5.5)]
        let updated = TrainingPlanGenerator.replan(plan, runs: runs, estimate: trainingEstimate, today: later, calendar: calendar)
        // Pasado y semana actual intactos; mismo número de semanas y misma carrera.
        #expect(Array(updated.weeks.prefix(current.index + 1)) == Array(plan.weeks.prefix(current.index + 1)))
        #expect(updated.weeks.count == plan.weeks.count)
        #expect(updated.weeks.last?.phase == .race)
        let next = updated.weeks[current.index + 1]
        #expect(next.distance < plan.weeks[current.index + 1].distance)
        #expect(updated.lastAdjustment?.reason == .behind)
        #expect(!TrainingPlanGenerator.needsWeeklyReplan(updated, today: later, calendar: calendar))
    }

    @Test func replanUpdatesPacesAfterATest() throws {
        let plan = try makePlan()
        let later = calendar.date(byAdding: .day, value: 10, to: today)!
        let test = PerformanceResult(date: later, distance: 5000, time: VDOT.raceTime(vdot: 46, distance: 5000), kind: .test)
        let estimate = try #require(FitnessEstimator.estimate(results: [test], runs: [], today: later, calendar: calendar))
        let updated = TrainingPlanGenerator.replan(plan, runs: [], estimate: estimate, today: later, calendar: calendar)
        #expect(abs((updated.vdot ?? 0) - 46) < 0.01)
        #expect(updated.paces.tempo.center.secondsPerKilometer < plan.paces.tempo.center.secondsPerKilometer)
        #expect(updated.lastAdjustment?.reason == .fitnessUpdated)
        #expect(abs((updated.lastAdjustment?.vdotChange ?? 0) - 2) < 0.01)
        // El objetivo sigue marcando el ritmo de carrera.
        #expect(updated.paces.race.secondsPerKilometer == 288)
    }

    @Test func oldPlansStillDecode() throws {
        // Plan guardado antes de los campos nuevos (sin vdot, ajuste ni tiempo objetivo).
        let plan = try makePlan()
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        json.removeValue(forKey: "vdot")
        json.removeValue(forKey: "lastAdjustment")
        var goal = try #require(json["goal"] as? [String: Any])
        goal.removeValue(forKey: "goalTime")
        json["goal"] = goal
        let decoded = try JSONDecoder().decode(TrainingPlan.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.vdot == nil && decoded.goal.goalTime == nil)
    }
}
