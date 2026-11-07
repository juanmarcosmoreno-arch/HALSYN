import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    calendar.firstWeekday = 2
    return calendar
}()
/// Sábado 7 de noviembre de 2026.
private let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 19))!
private func day(_ offset: Int, hour: Int = 18) -> Date {
    calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!)!
}

private func run(_ offset: Int, km: Double = 5, minutes: Double = 30, hr: Double? = 150, activity: WorkoutActivity = .outdoorRun) -> WorkoutSummary {
    let duration: TimeInterval = minutes * 60
    let distance: Double = km * 1000
    let maximum: Double? = hr.map { $0 + 10 }
    return WorkoutSummary(activity: activity, start: day(offset), duration: duration, distanceMeters: distance, averageHeartRate: hr, maxHeartRate: maximum, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
}

@Suite("Intensidad de los entrenamientos")
struct IntensityTests {
    @Test func heartRateBands() {
        #expect(IntensityClassifier.classify(run(0, minutes: 30, hr: 120), maxHeartRate: 186).kind == .recovery)
        #expect(IntensityClassifier.classify(run(0, minutes: 50, hr: 125), maxHeartRate: 186).kind == .easy)
        #expect(IntensityClassifier.classify(run(0, minutes: 40, hr: 140), maxHeartRate: 186).kind == .easy)
        #expect(IntensityClassifier.classify(run(0, minutes: 40, hr: 155), maxHeartRate: 186).kind == .moderate)
        #expect(IntensityClassifier.classify(run(0, km: 12, minutes: 80, hr: 164), maxHeartRate: 186).kind == .tempo)
        #expect(IntensityClassifier.classify(run(0, km: 4, minutes: 22, hr: 171), maxHeartRate: 186).kind == .maxEffort)
    }

    @Test func fastWithoutHeartRateIsNeverMaxEffort() {
        // 4 km a 4:30 sin pulso: rápido, pero sin evidencia de esfuerzo a tope.
        let fast = run(0, km: 4, minutes: 18, hr: nil)
        let intensity = IntensityClassifier.classify(fast, maxHeartRate: 186, thresholdPace: 330)
        #expect(intensity.kind == .tempo)
        #expect(intensity.isApproximate)
        #expect(IntensityClassifier.classify(fast, maxHeartRate: 186).kind == .unknown)
    }

    @Test func markedResultsWin() {
        #expect(IntensityClassifier.classify(run(0, hr: 120), maxHeartRate: 186, marked: .test).kind == .test)
        #expect(IntensityClassifier.classify(run(0, hr: 120), maxHeartRate: 186, marked: .race).kind == .race)
    }

    @Test func intervalPatternFromSamples() {
        // 6 series: 2 min a 175, 2 min a 140, una muestra cada 10 s.
        var points: [HeartRatePoint] = []
        var time = day(0)
        for _ in 0..<6 {
            for _ in 0..<12 { points.append(HeartRatePoint(date: time, bpm: 175)); time += 10 }
            for _ in 0..<12 { points.append(HeartRatePoint(date: time, bpm: 140)); time += 10 }
        }
        #expect(IntensityClassifier.isIntervalPattern(points, maxHeartRate: 186))
        let session = run(0, km: 6, minutes: 35, hr: 158)
        #expect(IntensityClassifier.classify(session, maxHeartRate: 186, samples: points).kind == .intervals)
        // Pulso estable: no son series.
        let start = day(0)
        let steady: [HeartRatePoint] = (0..<100).map { index in
            let offset: TimeInterval = Double(index) * 10
            let bpm: Double = 150 + Double(index % 3)
            return HeartRatePoint(date: start.addingTimeInterval(offset), bpm: bpm)
        }
        #expect(!IntensityClassifier.isIntervalPattern(steady, maxHeartRate: 186))
    }

    @Test func implausibleHeartRateFallsBackToPace() {
        let zero = run(0, km: 5, minutes: 30, hr: 0)
        let quality = DataQuality.assess([zero])[zero.id]
        let intensity = IntensityClassifier.classify(zero, maxHeartRate: 186, thresholdPace: 300, quality: quality)
        #expect(intensity.basis == .pace)
    }
}

@Suite("Volumen e intensidad semanal")
struct VolumeTests {
    @Test func averagesRestDaysAndStreaks() {
        // 3 carreras de 5 km por semana durante 12 semanas (lun, mié, vie).
        var runs: [WorkoutSummary] = []
        for week in 1...12 {
            for weekday in [0, 2, 4] {
                let offset: Int = weekday - 7 * week - 5
                runs.append(run(offset))
            }
        }
        let intensities = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, WorkoutIntensity(kind: .easy, basis: .heartRate)) })
        let analysis = TrainingVolumeAnalysis.compute(workouts: runs, intensities: intensities, today: today, calendar: calendar)
        #expect(analysis.weeks.count == TrainingVolumeAnalysis.weekCount)
        #expect(abs((analysis.average4 ?? 0) - 15_000) < 1)
        #expect(abs((analysis.average12 ?? 0) - 15_000) < 1)
        #expect(!analysis.isUnusualIncrease)
        #expect(analysis.intensityShare[.low] == 1)
        #expect(analysis.restDaysLast14 >= 8)
        #expect(analysis.longestStreakLast28 == 1)
    }

    @Test func suddenIncreaseIsRelativeToYourHistory() {
        var runs: [WorkoutSummary] = []
        for week in 2...10 {
            for weekday in [0, 2, 4] {
                let offset: Int = weekday - 7 * week - 5
                runs.append(run(offset))
            }
        }
        // Semana pasada: 6 carreras de 8 km (48 km frente a 15).
        for weekday in 0..<6 {
            let offset: Int = weekday - 12
            runs.append(run(offset, km: 8, minutes: 48))
        }
        let analysis = TrainingVolumeAnalysis.compute(workouts: runs, intensities: [:], today: today, calendar: calendar)
        #expect(analysis.isUnusualIncrease)
        #expect((analysis.lastWeekChange ?? 0) > 1)
        #expect(analysis.unclassifiedMinutes >= 0)
    }

    @Test func otherSportsCountForRestDaysButNotRunVolume() {
        let ride = run(-1, km: 30, minutes: 60, hr: 130, activity: .outdoorRide)
        let analysis = TrainingVolumeAnalysis.compute(workouts: [ride], intensities: [:], today: today, calendar: calendar)
        #expect(analysis.weeks.last?.runDistance == 0)
        #expect(analysis.weeks.last?.otherMinutes == 60)
        #expect(analysis.restDaysLast14 == 13)
    }
}

@Suite("Plan con eventos de salud")
struct HealthEventPlanTests {
    private func plan() -> TrainingPlan {
        let paces = TrainingPaces.from(vdot: 34, target: .fiveK)
        let kinds: [SessionKind] = [.intervals, .easy, .tempo, .rest, .easy, .rest, .long]
        let sessions = kinds.enumerated().map { index, kind in
            let distance: Double = kind == .rest ? 0 : (kind == .long ? 10_000 : 5000)
            return PlannedSession(date: calendar.startOfDay(for: day(index)), kind: kind, distance: distance, pace: paces.easy)
        }
        let goal = PlanGoal(distance: .fiveK, raceDate: day(70), runsPerWeek: 4, goalTime: 1500)
        return TrainingPlan(goal: goal, paces: paces, weeks: [PlannedWeek(index: 0, start: calendar.startOfDay(for: day(0)), phase: .build, sessions: sessions, level: nil)], createdAt: day(-30), startingWeeklyDistance: 15_000, vdot: 34, lastAdjustment: nil)
    }

    @Test func illnessSoftensAndNeverCompensates() {
        let sinus = HealthEvent(kind: .illness, title: "Sinusitis", start: day(-10), end: day(-1))
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: [], runs: [], maxHeartRate: 186, complaints: [], healthEvents: [sinus])
        #expect(advice.reasons.contains(.healthEvent(kind: .illness, title: "Sinusitis", ongoing: false)))
        for adjustment in advice.adjustments {
            #expect(adjustment.adjusted.distance <= adjustment.original.distance)
            #expect(!adjustment.adjusted.kind.isHard)
        }
        let adjusted = PlanAdvisor.apply(advice, to: plan())
        #expect(!adjusted.weeks[0].sessions.contains { $0.kind.isHard })
    }

    @Test func feverRestsFirst() {
        let fever = HealthEvent(kind: .fever, title: "", start: day(-1))
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: [], runs: [], maxHeartRate: 186, complaints: [], healthEvents: [fever])
        #expect(advice.adjustments.first?.change == .rested)
    }

    @Test func oldEventsDoNotChangeThePlan() {
        let old = HealthEvent(kind: .illness, title: "Gripe", start: day(-40), end: day(-30))
        let advice = PlanAdvisor.advise(plan: plan(), today: today, calendar: calendar, recovery: [], runs: [], maxHeartRate: 186, complaints: [], healthEvents: [old])
        #expect(!advice.reasons.contains { if case .healthEvent = $0 { true } else { false } })
    }

    @Test func eventDaysForAdherence() {
        let sinus = HealthEvent(kind: .illness, title: "Sinusitis", start: day(-3), end: day(-1))
        let vaccine = HealthEvent(kind: .vaccination, title: "", start: day(-2))
        let days = [sinus, vaccine].trainingAffectedDays(today: today, calendar: calendar)
        #expect(days.count == 3)
        #expect([sinus, vaccine].overlapping(from: day(-2), to: day(0), today: today, calendar: calendar).count == 2)
    }
}
