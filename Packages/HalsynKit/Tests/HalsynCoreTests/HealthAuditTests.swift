import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    calendar.firstWeekday = 2
    return calendar
}()
private func day(_ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

/// Del 8 de octubre al 7 de noviembre de 2026 (exportación de noviembre, anonimizada).
private enum November {
    static let hrv = [31.1, 46.0, 42.5, 46.0, 26.5, 30.3, 35.2, 44.0, 38.1, 23.7, 31.4, 28.0, 39.0, 17.5, 29.2, 36.9, 30.9, 33.1, 34.0, 32.3, 30.8, 43.8, 36.0, 32.7, 27.1, 31.0, 29.6, 27.0, 49.0, 49.8, 33.5]
    static let resting: [Double] = [64, 64, 62, 58, 64, 63, 61, 67, 68, 65, 66, 65, 69, 69, 74, 67, 67, 64, 68, 71, 65, 64, 63, 60, 68, 60, 71, 65, 58, 61, 62]
    static let sleep = [6.34, 7.12, 7.94, 6.33, 5.19, 5.09, 5.59, 6.45, 5.69, 6.20, 7.90, 6.92, 5.70, 6.17, 6.42, 3.03, 8.44, 10.64, 7.77, 7.38, 7.94, 6.12, 5.69, 6.51, 6.26, 5.08, 8.72, 5.96, 7.16, 7.07, 6.87]
    static let exercise: [Double] = [15, 44, 1, 3, 13, 18, 15, 8, 11, 11, 7, 36, 16, 14, 6, 46, 40, 3, 33, 1, 24, 34, 5, 42, 47, 40, 28, 53, 23, 36, 50]

    static func series(_ kind: MetricKind, _ values: [Double]) -> MetricSeries {
        let start = day(10, 8)
        return MetricSeries(kind: kind, values: values.enumerated().map { DailyValue(day: calendar.date(byAdding: .day, value: $0.offset, to: start)!, value: $0.element) }, origin: .demo)
    }

    static var history: DailyHistory {
        DailyHistory(series: [series(.heartRateVariability, hrv), series(.restingHeartRate, resting), series(.sleepDuration, sleep), series(.exerciseTime, exercise)], calendar: calendar)
    }
}

@Suite("Auditoría de salud: recuperación, sueño, laboratorio y exportación")
struct HealthAuditTests {
    // MARK: Recuperación del 7 de noviembre

    @Test func isolatedHRVDropDoesNotSinkRecovery() throws {
        let estimate = RecoveryEngine().evaluate(day: day(11, 7), history: November.history, origin: .demo)
        let hrv = try #require(estimate.components.first { $0.kind == .heartRateVariability })
        // La medición del día (33,5) está en la línea basal; la media de 3 días
        // (49,0 · 49,8 · 33,5 ≈ 44,1) queda por encima: no es un día negativo.
        #expect(hrv.singleDayValue == 33.5)
        #expect(abs((hrv.recentValue ?? 0) - 44.1) < 0.05)
        #expect((hrv.baselineValue ?? 99) < 35)
        #expect(hrv.impact != .negative)
        #expect(hrv.baselineDays >= 7)
        let value = try #require(estimate.value)
        #expect(value >= 80)
        // Todos los componentes explican sus valores.
        for component in estimate.components where component.score != nil {
            #expect(component.recentValue != nil)
        }
    }

    @Test func sustainedHRVDropDoesLowerIt() throws {
        var hrv = November.hrv
        hrv[hrv.count - 3] = 20
        hrv[hrv.count - 2] = 21
        hrv[hrv.count - 1] = 19
        let history = DailyHistory(series: [November.series(.heartRateVariability, hrv), November.series(.restingHeartRate, November.resting), November.series(.sleepDuration, November.sleep), November.series(.exerciseTime, November.exercise)], calendar: calendar)
        let estimate = RecoveryEngine().evaluate(day: day(11, 7), history: history, origin: .demo)
        #expect(estimate.components.first { $0.kind == .heartRateVariability }?.impact == .negative)
        let normal = RecoveryEngine().evaluate(day: day(11, 7), history: November.history, origin: .demo)
        #expect((estimate.value ?? 100) < (normal.value ?? 0))
    }

    @Test func missingDataIsNotZero() {
        let history = DailyHistory(series: [November.series(.restingHeartRate, November.resting)], calendar: calendar)
        let estimate = RecoveryEngine().evaluate(day: day(11, 7), history: history, origin: .demo)
        let missing = estimate.components.filter { $0.score == nil }.map(\.kind)
        #expect(missing.contains(.heartRateVariability))
        #expect(estimate.value == nil)
    }

    // MARK: Sueño

    @Test func afternoonNapDoesNotMoveTheNight() throws {
        // 2 nov: siesta 15:36–17:06, noche 23:00–06:42 (caso de la exportación).
        let samples = [
            SleepSample(start: day(11, 2, hour: 15, minute: 36), end: day(11, 2, hour: 17, minute: 6), stage: .asleepCore, sourceName: "Watch"),
            SleepSample(start: day(11, 2, hour: 23), end: day(11, 3, hour: 6, minute: 42), stage: .asleepCore, sourceName: "Watch"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: day(11, 3), calendar: calendar, origin: .demo))
        #expect(night.sleepStart == day(11, 2, hour: 23))
        #expect(night.episodes == 2)
        #expect(abs(night.napAsleep - 90 * 60) < 1)
        #expect(abs(night.asleep - (90 * 60 + 7 * 3600 + 42 * 60)) < 1)
        #expect(night.flags.contains(.napIncluded))
    }

    @Test func shortAndFragmentedNightsAreFlagged() throws {
        let samples = [
            SleepSample(start: day(10, 22, hour: 19), end: day(10, 22, hour: 21, minute: 30), stage: .asleepCore, sourceName: "Watch"),
            SleepSample(start: day(10, 22, hour: 20), end: day(10, 22, hour: 21), stage: .asleepCore, sourceName: "Phone"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: day(10, 23), calendar: calendar, origin: .demo))
        #expect(night.flags.contains(.shortRecord))
        #expect(night.flags.contains(.multipleSources))
        // Fusionadas sin contar dos veces.
        #expect(abs(night.asleep - (2 * 3600 + 30 * 60)) < 1)
    }

    @Test func repeatedShortSleepAndTiming() {
        let nights: [SleepNight] = (0..<14).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: day(11, 7))!
            let hours = offset < 3 ? 5.0 : 7.5
            let start = calendar.date(byAdding: .hour, value: offset == 5 ? -20 : -1, to: date)!
            let end = start.addingTimeInterval(hours * 3600)
            return SleepNight(day: date, asleep: hours * 3600, sleepStart: start, sleepEnd: end, awake: 0, stages: [:], sourceName: "Watch", origin: .demo)
        }
        let pattern = SleepPattern.analyze(nights, calendar: calendar)
        #expect(pattern.shortNightsLast7 == 3)
        #expect(pattern.repeatedShortSleep)
        #expect(pattern.unusualTimingDays.count == 1)
        #expect(pattern.average7 != nil)
    }

    // MARK: Laboratorio

    @Test func labUnitsAndReferences() throws {
        let factor = try #require(LabResult.Kind.ldl.alternative?.factor)
        #expect(abs(3.0 * factor - 116.01) < 0.01)
        let reference = try #require(LabReference.general(.fastingGlucose))
        #expect(reference.position(92) == .within)
        #expect(reference.position(110) == .above)
        #expect(LabReference.general(.hdl, sex: .female)?.lower == 50)
        #expect(LabReference.general(.weight) == nil)
        #expect(!LabResult(kind: .systolicPressure, date: .now, value: 12).isPlausible)
        let results = [LabResult(kind: .ldl, date: day(1, 10), value: 140), LabResult(kind: .ldl, date: day(9, 1), value: 120)]
        #expect(results.lastChange(.ldl) == -20)
    }

    // MARK: Exportación

    @Test func exportMarksComputedColumnsAndBlanksZeroHeartRate() {
        let zero = WorkoutSummary(activity: .outdoorRun, start: day(10, 28, hour: 18), duration: 80, distanceMeters: 268, averageHeartRate: 0, maxHeartRate: 0, activeEnergyKilocalories: 21, averageCadence: 157, origin: .healthKit(sourceName: "Apple Watch"))
        let extra = DataExport.WorkoutExtra(intensity: "easy", intensityBasis: "pace", qualityFlags: ["too_short", "implausible_hr"], modelRole: "", modelWeight: nil)
        let csv = DataExport.workoutsCSV([zero], extras: [zero.id: extra], calendar: calendar)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = lines[0].split(separator: ",").map(String.init)
        let cells = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(header.count == cells.count)
        #expect(cells[header.firstIndex(of: "avg_hr_bpm")!] == "")
        #expect(cells[header.firstIndex(of: "max_hr_bpm")!] == "")
        #expect(cells[header.firstIndex(of: "source")!] == "Apple Watch")
        #expect(cells[header.firstIndex(of: "quality_flags")!] == "too_short|implausible_hr")
        #expect(cells[header.firstIndex(of: "record_id")!].count == 8)
        for column in DataExport.computedWorkoutColumns {
            #expect(header.contains(column))
        }
        // Columnas antiguas en el mismo orden (compatibilidad).
        #expect(Array(header.prefix(17)) == Array(DataExport.workoutHeader.prefix(17)))
    }

    @Test func recordIDIsStableAndShort() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        #expect(DataExport.recordID(id) == DataExport.recordID(id))
        #expect(DataExport.recordID(id) != DataExport.recordID(UUID()))
    }

    @Test func evidenceEventsAndLabsCSV() throws {
        let test = PerformanceResult(date: day(11, 2, hour: 18), distance: 4005, time: 1326, kind: .test)
        let model = try #require(RacePerformanceModel.assess(results: [test], runs: [], today: day(11, 7, hour: 19), calendar: calendar))
        let evidence = DataExport.evidenceCSV(model, calendar: calendar)
        #expect(evidence.contains("2026-11-02,test,4.005,1326,"))
        #expect(evidence.contains(",counted,"))
        let events = DataExport.healthEventsCSV([HealthEvent(kind: .illness, title: "Sinusitis, leve", start: day(10, 5), end: day(10, 20))], calendar: calendar)
        #expect(events.contains("2026-10-05,2026-10-20,illness,\"Sinusitis, leve\","))
        let labs = DataExport.labResultsCSV([LabResult(kind: .fastingGlucose, date: day(9, 1), value: 92)], calendar: calendar)
        #expect(labs.contains("2026-09-01,fastingGlucose,,92.00,mg/dL,"))
        #expect(labs.contains("ADA"))
    }

    @Test func qualitySummaryCountsFlags() {
        let zero = WorkoutSummary(activity: .outdoorRun, start: day(10, 28, hour: 18), duration: 80, distanceMeters: 268, averageHeartRate: 0, maxHeartRate: 0, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        let noDistance = WorkoutSummary(activity: .outdoorRun, start: day(10, 23, hour: 7), duration: 543, distanceMeters: nil, averageHeartRate: 72, maxHeartRate: 79, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        let summary = Dictionary(uniqueKeysWithValues: DataExport.qualitySummary([zero, noDistance]).map { ($0.code, $0.count) })
        #expect(summary["too_short"] == 1)
        #expect(summary["missing_distance"] == 1)
        #expect(summary["implausible_hr"] == 1)
    }
}
