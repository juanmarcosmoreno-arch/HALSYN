import Foundation
import Testing
@testable import HalsynCore

/// Auditoría técnica de los motores, Fase B (RacePerformanceModel 1.5,
/// HealthScoreEngine 0.2). Cada prueba verifica una propiedad, no un número copiado.
@Suite("Auditoría de motores · Fase B")
struct EngineAuditPhaseBTests {
    private let calendar = NovemberFixture.calendar
    private let runs = NovemberFixture.runs
    private let test31 = PerformanceResult(date: NovemberFixture.run(10, 31, 18).start, distance: 3026, time: 951, kind: .test, workoutID: NovemberFixture.run(10, 31, 18).id)
    private let test2 = PerformanceResult(date: NovemberFixture.run(11, 2, 18).start, distance: 4005, time: 1326, kind: .test, workoutID: NovemberFixture.run(11, 2, 18).id)
    private let manual31 = PerformanceResult(date: NovemberFixture.calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!, distance: 3000, time: 951, kind: .test)

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    /// Plan con sesiones lun, mié, vie y dom de la semana del 2/11.
    private func plan(kinds: [SessionKind] = [.easy, .easy, .easy, .long]) -> TrainingPlan {
        let paces = TrainingPaces.from(vdot: 34, target: .fiveK)
        let sessions = zip([0, 2, 4, 6], kinds).map { offset, kind in
            PlannedSession(date: calendar.date(byAdding: .day, value: offset, to: monday)!, kind: kind, distance: 4000, pace: paces.easy)
        }
        let race = calendar.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 9))!
        let goal = PlanGoal(distance: .fiveK, raceDate: race, runsPerWeek: 4, goalTime: 1500)
        return TrainingPlan(goal: goal, paces: paces, weeks: [PlannedWeek(index: 0, start: monday, phase: .build, sessions: sessions, level: nil)], createdAt: monday, startingWeeklyDistance: 15_000, vdot: 34, lastAdjustment: nil)
    }

    private func run(_ day: Int, km: Double = 4) -> WorkoutSummary {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 7))!
        let distance: Double = km * 1000
        let duration: TimeInterval = km * 360
        return WorkoutSummary(activity: .outdoorRun, start: start, duration: duration, distanceMeters: distance, averageHeartRate: 150, maxHeartRate: 170, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
    }

    // MARK: 2.1 Cumplimiento en semanas parciales

    @Test func partialWeekIsComparedWithScheduledSessions() throws {
        // Caso real: 3 de 3 sesiones programadas hasta el sábado 7/11.
        let adherence = TrainingAdherence.evaluate(plan: plan(), runs: [run(2), run(4), run(6)], today: NovemberFixture.today, calendar: calendar)
        #expect(adherence.scheduledInWindow == 3)
        #expect(adherence.runDays == 3)
        #expect(adherence.frequencyRatio == 1)
        #expect(adherence.effective == 1)
        #expect(adherence.isLimited)
        // Con poco dato se mezcla con el supuesto: (3 × 1 + 4 × 0,85) ÷ 7.
        let expected: Double = (3 + 4 * 0.85) / 7
        let used = try #require(adherence.projectionCompliance)
        #expect(abs(used - expected) < 1e-12)
        // 1.6: rampa continua (c − 0,4) ÷ 0,6 = 0,857 (en 1.5 se cortaba en 90 % y daba 1).
        let factor: Double = (expected - 0.4) / 0.6
        #expect(abs(GoalProbability.gainFactor(used) - factor) < 1e-12)
    }

    @Test func missingSessionStillCounts() {
        let adherence = TrainingAdherence.evaluate(plan: plan(), runs: [run(2), run(4)], today: NovemberFixture.today, calendar: calendar)
        #expect(adherence.planned == 3)
        #expect(adherence.missed == 1)
        let ratio: Double = 2.0 / 3.0
        #expect(abs(adherence.frequencyRatio - ratio) < 1e-12)
    }

    @Test func excusedSessionsDoNotLowerFrequency() {
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let adherence = TrainingAdherence.evaluate(plan: plan(), runs: [run(2), run(6)], today: NovemberFixture.today, calendar: calendar, skips: [wednesday: .illness])
        #expect(adherence.excused == 1)
        #expect(adherence.frequencyRatio == 1)
    }

    @Test func noPastSessionsMeansNoData() {
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 20))!
        let adherence = TrainingAdherence.evaluate(plan: plan(), runs: [], today: saturday, calendar: calendar)
        #expect(adherence.planned == 0)
        #expect(adherence.projectionCompliance == nil)
    }

    @Test func correctedProjectionForTheRealCase() throws {
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let probability = try #require(GoalProbability.evaluate(plan: plan(), performance: model, runs: [run(2), run(4), run(6)], today: NovemberFixture.today, calendar: calendar))
        let central = try #require(probability.central)
        #expect(central.weeks == 9)
        let compliance: Double = (3 + 4 * 0.85) / 7
        let factor: Double = (compliance - 0.4) / 0.6
        #expect(abs(central.complianceFactor - factor) < 1e-12)
        // Sin tendencia estimable: tasa = 1/6 × factor; mejora = 4 × (1 − e^(−9 × tasa ÷ 4)).
        let rate: Double = factor / 6
        let exponent: Double = -9.0 * rate / 4.0
        let expected: Double = 4 * (1 - Foundation.exp(exponent))
        #expect(central.adaptation?.state == .reference)
        #expect(abs(central.gain - expected) < 1e-9)
        #expect(probability.projectedTime < VDOT.raceTime(vdot: model.currentVDOT + 0.9235, distance: 5000))
    }

    // MARK: 1.3 Una sola definición de «hoy»

    @Test func todayIsTheSameEverywhere() throws {
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let probability = try #require(GoalProbability.evaluate(plan: plan(), performance: model, runs: runs, today: NovemberFixture.today, calendar: calendar))
        let prediction = model.predict(5000)
        #expect(prediction.time == probability.currentTime)
        #expect(prediction.time == VDOT.raceTime(vdot: model.currentVDOT, distance: 5000))
        // Riegel queda dentro del rango orientativo.
        let range = try #require(prediction.range)
        #expect(range.contains(prediction.riegelTime))
    }

    // MARK: 1.4 / 6.3 Reimportaciones

    @Test func reimportDoesNotChangeTheModel() throws {
        let copies = runs.map { WorkoutSummary(activity: $0.activity, start: $0.start.addingTimeInterval(20), duration: $0.duration, distanceMeters: $0.distanceMeters, averageHeartRate: $0.averageHeartRate, maxHeartRate: $0.maxHeartRate, activeEnergyKilocalories: nil, averageCadence: $0.averageCadence, origin: .healthKit(sourceName: "Otra app"), elevationGain: $0.elevationGain) }
        let both = runs + copies
        #expect(EffortClassifier.referenceMaxHeartRate(configured: nil, runs: both) == EffortClassifier.referenceMaxHeartRate(configured: nil, runs: runs))
        #expect(HeartRateZoneConfiguration.observedMax(in: both) == HeartRateZoneConfiguration.observedMax(in: runs))
        let single = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let doubled = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: both, today: NovemberFixture.today, calendar: calendar))
        #expect(single.currentVDOT == doubled.currentVDOT)
        #expect(single.evidence.map(\.role) == doubled.evidence.map(\.role))
    }

    @Test func copyOfAMarkedWorkoutIsNotCountedTwice() throws {
        let marked = NovemberFixture.run(10, 31, 18)
        let copy = WorkoutSummary(activity: .outdoorRun, start: marked.start.addingTimeInterval(5), duration: marked.duration, distanceMeters: marked.distanceMeters, averageHeartRate: marked.averageHeartRate, maxHeartRate: marked.maxHeartRate, activeEnergyKilocalories: nil, averageCadence: marked.averageCadence, origin: .healthKit(sourceName: "Otra app"), elevationGain: marked.elevationGain)
        // La copia sola (sin el original, como queda tras limpiar si se conserva la copia).
        let others = runs.filter { $0.id != marked.id } + [copy]
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: others, today: NovemberFixture.today, calendar: calendar))
        #expect(!model.evidence.contains { $0.id == copy.id })
    }

    // MARK: 1.5 / 1.7 Deduplicación determinista

    @Test func deduplicationIsOrderIndependentAndIdempotent() {
        let manualB = PerformanceResult(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 20))!, distance: 3010, time: 955, kind: .test)
        let inputs = [manual31, manualB, test31, test2]
        let reference = Set(RacePerformanceModel.deduplicated(inputs, calendar: calendar).kept.map(\.id))
        for permutation in [inputs.reversed(), [manualB, test2, manual31, test31], [test2, test31, manualB, manual31]] {
            #expect(Set(RacePerformanceModel.deduplicated(Array(permutation), calendar: calendar).kept.map(\.id)) == reference)
        }
        let kept = RacePerformanceModel.deduplicated(inputs, calendar: calendar).kept
        #expect(RacePerformanceModel.deduplicated(kept, calendar: calendar).kept.map(\.id) == kept.map(\.id))
        #expect(reference.contains(test31.id))
    }

    @Test func duplicateAcrossMidnightIsDetected() {
        let late = PerformanceResult(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 50))!, distance: 3026, time: 951, kind: .test, workoutID: UUID())
        let nextDay = PerformanceResult(date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 10))!, distance: 3000, time: 951, kind: .test)
        #expect(RacePerformanceModel.deduplicated([late, nextDay], calendar: calendar).kept.count == 1)
        // Sesiones distintas el mismo día no se fusionan.
        let other = PerformanceResult(date: late.date, distance: 5000, time: 1680, kind: .test)
        #expect(RacePerformanceModel.deduplicated([late, other], calendar: calendar).kept.count == 2)
    }

    // MARK: 1.8 / 3.1 / 3.2 / 3.3 Intensidad y elegibilidad

    @Test func plannedQualitySessionsNeedConfirmation() {
        let effort = NovemberFixture.run(11, 1, 6)
        #expect(EffortClassifier.eligibility(effort, maxHeartRate: 186, plannedKind: .tempo) == .notEligible(.plannedWorkout))
        #expect(EffortClassifier.eligibility(effort, maxHeartRate: 186, plannedKind: .intervals) == .notEligible(.plannedWorkout))
        #expect(EffortClassifier.eligibility(effort, maxHeartRate: 186, plannedKind: .intervals, marked: .test) == .confirmed)
    }

    @Test func configuredMaxIsRespectedAndWarned() {
        // 0.10.0 (107): la configurada no se reemplaza en silencio.
        let today = NovemberFixture.today
        let cal = NovemberFixture.calendar
        let manual = HeartRateZoneConfiguration(maxSource: .manual, maxHeartRate: 180)
        let low = HeartRateZoneConfiguration.resolveMax(manual, runs: runs, today: today, calendar: cal)
        #expect(low.value == 180)
        #expect(low.configuredBelowValidated)
        let close = HeartRateZoneConfiguration.resolveMax(HeartRateZoneConfiguration(maxSource: .manual, maxHeartRate: 185), runs: runs, today: today, calendar: cal)
        #expect(close.value == 185)
        #expect(!close.configuredBelowValidated)
        let empty = HeartRateZoneConfiguration.resolveMax(HeartRateZoneConfiguration(maxSource: .manual), runs: runs, today: today, calendar: cal)
        #expect(empty.value == empty.validated)
        #expect(empty.usesValidatedFallback)
        var validated = manual
        validated.configuredMaxHeartRate = 180
        validated.maxSource = .validated
        let chosen = HeartRateZoneConfiguration.resolveMax(validated, runs: runs, today: today, calendar: cal)
        #expect(chosen.value == chosen.validated)
        #expect(chosen.configured == 180)
        validated.maxSource = .observed
        #expect(HeartRateZoneConfiguration.resolveMax(validated, runs: runs, today: today, calendar: cal).value == chosen.recorded)
    }

    @Test func lactateThresholdZones() {
        func classify(_ hr: Double) -> IntensityClass {
            let workout = WorkoutSummary(activity: .outdoorRun, start: NovemberFixture.today, duration: 1800, distanceMeters: 5000, averageHeartRate: hr, maxHeartRate: hr + 10, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
            return IntensityClassifier.classify(workout, maxHeartRate: 186, lactateThreshold: 170).kind
        }
        #expect(classify(140) == .recovery)
        #expect(classify(150) == .easy)
        #expect(classify(156) == .moderate)
        #expect(classify(166) == .tempo)
        #expect(classify(172) == .veryHard)
    }

    @Test func harderThanPlannedIsFlagged() {
        let run7 = NovemberFixture.run(11, 7, 9)
        let long = IntensityClassifier.classify(run7, maxHeartRate: 184, plannedKind: .long)
        #expect(long.sessionType == .long)
        #expect(long.harderThanPlanned)
        let unplanned = IntensityClassifier.classify(run7, maxHeartRate: 184)
        #expect(!unplanned.harderThanPlanned)
        let easyDone = IntensityClassifier.classify(NovemberFixture.run(10, 29, 18), maxHeartRate: 186, plannedKind: .easy)
        #expect(!easyDone.harderThanPlanned)
    }

    @Test func missingHeartRateIsNotMaximalAndNotZero() {
        let noHR = WorkoutSummary(activity: .outdoorRun, start: NovemberFixture.today, duration: 1200, distanceMeters: 4000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        #expect(EffortClassifier.eligibility(noHR, maxHeartRate: 186) == .notEligible(.noHeartRate))
        #expect(IntensityClassifier.classify(noHR, maxHeartRate: 186).kind == .unknown)
        let csv = DataExport.workoutsCSV([noHR], calendar: calendar)
        #expect(csv.contains(",,,"))
    }

    // MARK: 2.2 / 2.5 Proyección

    @Test func projectionEdges() throws {
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let zero = GoalProjection.project(performance: model, weeks: 0, compliance: 1, runsPerWeek: 4, scenario: .central)
        #expect(zero.gain == 0)
        let one = GoalProjection.project(performance: model, weeks: 1, compliance: 1, runsPerWeek: 4, scenario: .central)
        let many = GoalProjection.project(performance: model, weeks: 200, compliance: 1, runsPerWeek: 4, scenario: .central)
        #expect(one.gain > 0 && one.gain < 1.0 / 6.0 + 1e-9)
        #expect(many.gain < GoalProjection.improvementCap)
        #expect(many.uncertainty > one.uncertainty)
    }

    @Test func futureIllnessReducesEffectiveWeeks() throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        let events = [HealthEvent(kind: .injury, title: "", start: start, end: end), HealthEvent(kind: .vaccination, title: "", start: start, end: end)]
        let race = calendar.date(from: DateComponents(year: 2027, month: 1, day: 18))!
        let days = events.blockedFutureDays(today: NovemberFixture.today, until: race, calendar: calendar)
        #expect(days == 14)
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let probability = try #require(GoalProbability.evaluate(plan: plan(), performance: model, runs: runs, today: NovemberFixture.today, calendar: calendar, blockedFutureDays: days))
        #expect(probability.blockedWeeks == 2)
        #expect(probability.central?.weeks == 7)
    }

    // MARK: 4.5 Plan y recuperación

    @Test func aggregateScoreAloneDoesNotTriggerFatigue() {
        let today = NovemberFixture.today
        let recovery: [(day: Date, value: Int?)] = (0..<30).map { offset in
            (day: calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))!, value: offset < 3 ? 40 : 80)
        }
        #expect(PlanAdvisor.lowRecovery(recovery, today: today, calendar: calendar) != nil)
        #expect(PlanAdvisor.lowRecovery(recovery, today: today, calendar: calendar, physiologicalLowDays: []) == nil)
    }

    // MARK: 5.1 / 5.2 HealthScoreEngine 0.2

    @Test func healthScoreSleepMatchesRecovery() throws {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        func series(_ kind: MetricKind, _ value: Double) -> MetricSeries {
            MetricSeries(kind: kind, values: (0..<40).map { DailyValue(day: calendar.date(byAdding: .day, value: -$0, to: day)!, value: $0 == 0 && kind == .sleepDuration ? 3.03 : value + Double($0 % 3)) }, origin: .demo)
        }
        let history = DailyHistory(series: [series(.sleepDuration, 6.5), series(.restingHeartRate, 64), series(.heartRateVariability, 34), series(.steps, 7000), series(.exerciseTime, 25)], calendar: calendar)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 19))!
        let incomplete = SleepNight(day: day, asleep: 10_908, sleepStart: start, sleepEnd: start.addingTimeInterval(11_520), awake: 0, stages: [:], sourceName: "Watch", origin: .demo)
        #expect(incomplete.flags.contains(.shortRecord))
        let engine = HealthScoreEngine()
        let without = engine.evaluate(day: day, history: history)
        let with = engine.evaluate(day: day, history: history, nights: [day: incomplete])
        #expect(without.breakdown.dimensions.first { $0.dimension == .sleep }?.score != nil)
        #expect(with.breakdown.dimensions.first { $0.dimension == .sleep }?.score == nil)
        #expect(HealthScoreEngine.version == "0.2-provisional")
    }

    @Test func oneOutlierDoesNotMoveTheHealthBaseline() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        func history(outlier: Double?) -> DailyHistory {
            let values: [DailyValue] = (0..<40).map { offset in
                let value: Double = offset == 10 ? (outlier ?? 62) : 62 + Double(offset % 3)
                return DailyValue(day: calendar.date(byAdding: .day, value: -offset, to: day)!, value: value)
            }
            return DailyHistory(series: [MetricSeries(kind: .restingHeartRate, values: values, origin: .demo)], calendar: calendar)
        }
        let engine = HealthScoreEngine()
        let normal = engine.evaluate(day: day, history: history(outlier: nil)).breakdown.dimensions.first { $0.dimension == .cardiovascular }?.score
        let withOutlier = engine.evaluate(day: day, history: history(outlier: 95)).breakdown.dimensions.first { $0.dimension == .cardiovascular }?.score
        #expect(normal == withOutlier)
    }

    // MARK: 12 Coherencia interna ↔ exportación

    @Test func exportReflectsTheEngine() throws {
        let model = try #require(RacePerformanceModel.assess(results: [manual31, test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let csv = DataExport.evidenceCSV(model, results: [manual31, test31, test2], calendar: calendar)
        for item in model.evidence {
            #expect(csv.contains(DataExport.recordID(item.id) + ","))
            #expect(csv.contains("," + DataExport.number(item.weight, digits: 3) + ","))
        }
        let total = model.countedEvidence.map(\.weight).reduce(0, +)
        let weighted = model.countedEvidence.map { $0.weight * ($0.valueUsed ?? 0) }.reduce(0, +)
        #expect(abs(weighted / total - model.currentVDOT) < 1e-9)
        #expect(RacePerformanceModel.version == "1.6")
    }
}
