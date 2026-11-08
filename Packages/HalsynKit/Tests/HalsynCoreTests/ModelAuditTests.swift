import Foundation
import Testing
@testable import HalsynCore

/// Auditoría posterior a RacePerformanceModel 1.3 (datos reales del 7/11/2026).
@Suite("Auditoría del modelo 1.4: elegibilidad, duplicados, recuperación y proyección")
struct ModelAuditTests {
    private let calendar = NovemberFixture.calendar
    private let runs = NovemberFixture.runs

    private var reference: Double? {
        let quality = DataQuality.assess(runs)
        return EffortClassifier.referenceMaxHeartRate(configured: nil, runs: runs.filter { quality[$0.id]?.heartRateUsable != false })
    }

    private let test31 = PerformanceResult(date: NovemberFixture.run(10, 31, 18).start, distance: 3026, time: 951, kind: .test, workoutID: NovemberFixture.run(10, 31, 18).id)
    private let test2 = PerformanceResult(date: NovemberFixture.run(11, 2, 18).start, distance: 4005, time: 1326, kind: .test, workoutID: NovemberFixture.run(11, 2, 18).id)
    private let manual31 = PerformanceResult(date: NovemberFixture.calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!, distance: 3000, time: 951, kind: .test)

    // MARK: Elegibilidad (puntos 1, 2, 6 y 8)

    @Test func referenceMaxUsesAllRuns() {
        // Con todas las carreras (cinta incluida) la referencia es 186; antes,
        // solo con las de aire libre, era 182 y los rodajes del 6 y 7/11 pasaban por «a tope».
        #expect(reference == 186)
    }

    @Test func highHeartRateIsNotAutomaticallyMaximal() throws {
        let reference = try #require(reference)
        let quality = DataQuality.assess(runs)
        let run7 = NovemberFixture.run(11, 7, 9)
        let run6 = NovemberFixture.run(11, 6, 18)
        // Intensidad fisiológica alta…
        #expect(IntensityClassifier.classify(run7, maxHeartRate: reference, quality: quality[run7.id]).kind == .tempo)
        // …pero no candidatos a prueba.
        #expect(EffortClassifier.eligibility(run7, maxHeartRate: reference, quality: quality[run7.id]) == .notEligible(.lowHeartRate))
        #expect(EffortClassifier.eligibility(run6, maxHeartRate: 184, quality: quality[run6.id]) == .notEligible(.hilly))
        // Los tres esfuerzos de verdad siguen siendo candidatos.
        for (month, day, hour) in [(10, 31, 18), (11, 1, 6), (11, 2, 18)] {
            let run = NovemberFixture.run(month, day, hour)
            #expect(EffortClassifier.eligibility(run, maxHeartRate: reference, quality: quality[run.id]) == .candidate)
            #expect(IntensityClassifier.classify(run, maxHeartRate: reference, quality: quality[run.id]).kind == .veryHard)
        }
    }

    @Test func plannedEasySessionAndRejectionAreNotEligible() {
        let run = NovemberFixture.run(11, 1, 6)
        #expect(EffortClassifier.eligibility(run, maxHeartRate: 186, plannedKind: .easy) == .notEligible(.plannedEasy))
        #expect(EffortClassifier.eligibility(run, maxHeartRate: 186, rejected: true) == .notEligible(.rejected))
        #expect(EffortClassifier.eligibility(run, maxHeartRate: 186, marked: .test) == .confirmed)
        #expect(EffortClassifier.eligibility(run, maxHeartRate: 186, thresholdHeartRate: 172) == .notEligible(.belowThreshold))
    }

    @Test func modelEvidenceMatchesTheExport() throws {
        let model = try #require(RacePerformanceModel.assess(results: [manual31, test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        // Ya no aparecen el 6 ni el 7/11; el 1/11 queda como candidato no confirmado.
        #expect(!model.evidence.contains { $0.id == NovemberFixture.run(11, 7, 9).id })
        #expect(!model.evidence.contains { $0.id == NovemberFixture.run(11, 6, 18).id })
        let run1 = try #require(model.evidence.first { $0.id == NovemberFixture.run(11, 1, 6).id })
        #expect(run1.role == .belowEstimate)
        #expect(abs(model.currentVDOT - 34.344) < 0.01)
    }

    @Test func farBelowCandidateIsNotMaximal() throws {
        // Con una FC máxima configurada de 184, el 7/11 pasa el 90 %, pero su
        // VDOT (30,5) está más de 3 puntos por debajo de los tests.
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, maxHeartRate: 184, today: NovemberFixture.today, calendar: calendar))
        #expect(model.evidence.first { $0.id == NovemberFixture.run(11, 7, 9).id }?.role == .notMaximal)
    }

    @Test func confirmedSlowerEffortLowersTheEstimate() throws {
        let before = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let run1 = NovemberFixture.run(11, 1, 6)
        let confirmed = PerformanceResult(date: run1.start, distance: 4005, time: run1.duration, kind: .test, workoutID: run1.id)
        let after = try #require(RacePerformanceModel.assess(results: [test31, test2, confirmed], runs: runs, today: NovemberFixture.today, calendar: calendar))
        #expect(after.currentVDOT < before.currentVDOT)
        let rejected = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, rejected: [run1.id], today: NovemberFixture.today, calendar: calendar))
        #expect(!rejected.evidence.contains { $0.id == run1.id })
    }

    // MARK: Duplicados (punto 3)

    @Test func resultsCSVTracesBothRecords() {
        let results = [manual31, test31, test2]
        let csv = DataExport.resultsCSV(results, calendar: calendar)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        let manualLine = lines.first { $0.contains(DataExport.recordID(manual31.id)) } ?? ""
        #expect(manualLine.contains(",manual,"))
        #expect(manualLine.contains(",duplicate,"))
        #expect(manualLine.contains(DataExport.recordID(test31.id)))
        let workoutLine = lines.first { $0.contains(DataExport.recordID(test31.id) + ",") && $0.contains(",workout,") } ?? ""
        #expect(workoutLine.contains(DataExport.recordID(NovemberFixture.run(10, 31, 18).id)))
        #expect(workoutLine.contains(",used,"))
    }

    @Test func evidenceCSVLinksDuplicates() throws {
        let model = try #require(RacePerformanceModel.assess(results: [manual31, test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let csv = DataExport.evidenceCSV(model, results: [manual31, test31, test2], calendar: calendar)
        #expect(csv.contains(",duplicate,"))
        #expect(csv.contains(DataExport.recordID(test31.id)))
        #expect(csv.contains(",unconfirmed_below_estimate,"))
    }

    // MARK: Proyección (punto 5)

    @Test func projectionArithmetic() throws {
        let model = try #require(RacePerformanceModel.assess(results: [test31, test2], runs: runs, today: NovemberFixture.today, calendar: calendar))
        let race = calendar.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 9))!
        let weeks = GoalCoach.trainingWeeks(until: race, distance: .fiveK, today: NovemberFixture.today, calendar: calendar)
        #expect(weeks == 9)
        let result = GoalProjection.project(performance: model, weeks: weeks, compliance: 0.75, runsPerWeek: 4, scenario: .central)
        // Pauta de Daniels (tendencia provisional): 1/6 VDOT por semana.
        #expect(!result.usesPersonalTrend)
        #expect(abs(result.rate - 1.0 / 6.0) < 1e-12)
        // Cumplimiento 75 % → (0,75 − 0,4) ÷ 0,5 = 0,7.
        #expect(abs(result.complianceFactor - 0.7) < 1e-12)
        #expect(result.frequencyFactor == 1)
        // 4 × (1 − e^(−9 × (1/6) × 0,7 ÷ 4)) = 0,9235.
        let exponent: Double = -9.0 * (1.0 / 6.0) * 0.7 / 4.0
        let expected: Double = 4 * (1 - Foundation.exp(exponent))
        #expect(abs(result.gain - expected) < 1e-9)
        #expect(abs(result.gain - 0.9235) < 0.0001)
        let today = VDOT.raceTime(vdot: model.currentVDOT, distance: 5000)
        let raceDay = VDOT.raceTime(vdot: result.projectedVDOT, distance: 5000)
        #expect(abs(today - 1644.5) < 1)
        #expect(abs(raceDay - 1608.3) < 1)
    }

    // MARK: Recuperación y sueño (puntos 4 y 10)

    @Test func historyCoversTheSevenDayWindow() {
        #expect(RecoveryEngine().historyDaysNeeded == 35)
    }

    @Test func napAndIncompleteNightsInRecovery() throws {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        func series(_ kind: MetricKind, _ value: Double) -> MetricSeries {
            MetricSeries(kind: kind, values: (0..<40).map { DailyValue(day: calendar.date(byAdding: .day, value: -$0, to: day)!, value: value + Double($0 % 3)) }, origin: .demo)
        }
        let history = DailyHistory(series: [series(.heartRateVariability, 35), series(.restingHeartRate, 63), series(.sleepDuration, 7), series(.exerciseTime, 25)], calendar: calendar)
        func night(_ offset: Int, main: Double, nap: Double = 0) -> SleepNight {
            let date = calendar.date(byAdding: .day, value: -offset, to: day)!
            let mainSeconds: TimeInterval = main * 3600
            let napSeconds: TimeInterval = nap * 3600
            let start = calendar.date(byAdding: .hour, value: -1, to: date)!
            var value = SleepNight(day: date, asleep: mainSeconds + napSeconds, sleepStart: start, sleepEnd: start.addingTimeInterval(mainSeconds), awake: 0, stages: [:], sourceName: "Watch", origin: .demo)
            value.napAsleep = napSeconds
            value.episodes = nap > 0 ? 2 : 1
            return value
        }
        var nights: [Date: SleepNight] = [:]
        for offset in 1...30 { nights[calendar.date(byAdding: .day, value: -offset, to: day)!] = night(offset, main: 7) }
        // 3/11: 7,2 h de noche + 1,5 h de siesta → el sueño de la noche es 7,2 h.
        nights[day] = night(0, main: 7.2, nap: 1.5)
        let withNap = RecoveryEngine().evaluate(day: day, history: history, origin: .demo, nights: nights)
        let sleep = try #require(withNap.components.first { $0.kind == .sleep })
        #expect(abs((sleep.recentValue ?? 0) - 7.2) < 0.001)
        #expect(abs((sleep.napHours ?? 0) - 1.5) < 0.001)
        // Registro de 2,5 h cuando lo habitual son 7: incompleto, no se usa.
        nights[day] = night(0, main: 2.5)
        let incomplete = RecoveryEngine().evaluate(day: day, history: history, origin: .demo, nights: nights)
        let short = try #require(incomplete.components.first { $0.kind == .sleep })
        #expect(short.score == nil)
        #expect(short.possiblyIncomplete)
        #expect(incomplete.value != nil)
    }
}
