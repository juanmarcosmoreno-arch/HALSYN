import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Montevideo")!
    calendar.firstWeekday = 2
    return calendar
}()
private func date(_ day: Int, _ month: Int, hour: Int = 8) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

/// Los datos de la exportación del usuario (regresión).
private enum Export {
    static let runID = UUID()
    static let duplicateManual = PerformanceResult(date: date(31, 10), distance: 3000, time: 15 * 60 + 51, kind: .test)
    static let duplicateMarked = PerformanceResult(date: date(31, 10, hour: 9), distance: 3026, time: 15 * 60 + 51, kind: .test, workoutID: runID)
    static let test4k = PerformanceResult(date: date(2, 11), distance: 4005, time: 22 * 60 + 6, kind: .test)
    /// Rodaje con pulso alto (el sensor lo hacía pasar por esfuerzo) y VDOT ~30,5.
    static let easyRun = WorkoutSummary(activity: .outdoorRun, start: date(7, 11), duration: 36 * 60 + 51, distanceMeters: 6024, averageHeartRate: 172, maxHeartRate: 180, activeEnergyKilocalories: nil, averageCadence: 164, origin: .healthKit(sourceName: "Apple Watch"))
    static let today = date(7, 11, hour: 20)
}

@Suite("Auditoría del motor de predicción (datos reales)")
struct PredictionAuditTests {
    @Test func slowerRunDoesNotLowerVDOT() throws {
        let model = try #require(RacePerformanceModel.assess(results: [Export.duplicateManual, Export.duplicateMarked, Export.test4k], runs: [Export.easyRun], maxHeartRate: 185, today: Export.today, calendar: calendar))
        // Antes salía 33,4: por debajo de los dos tests. Ahora no puede quedar por debajo del peor test.
        #expect(model.currentVDOT >= (Export.test4k.vdot ?? 0) - 0.01)
        #expect(model.currentVDOT <= (Export.duplicateMarked.vdot ?? 99))
        let run = try #require(model.evidence.first { $0.id == Export.easyRun.id })
        #expect(run.role == .belowEstimate)
        #expect(run.weight == 0)
    }

    @Test func duplicatedTestCountsOnce() throws {
        let (kept, duplicates) = RacePerformanceModel.deduplicated([Export.duplicateManual, Export.duplicateMarked, Export.test4k], calendar: calendar)
        #expect(kept.count == 2)
        // Se queda el que viene del entrenamiento (distancia exacta).
        #expect(kept.contains { $0.id == Export.duplicateMarked.id })
        #expect(duplicates.first?.0.id == Export.duplicateManual.id)
        let model = try #require(RacePerformanceModel.assess(results: [Export.duplicateManual, Export.duplicateMarked, Export.test4k], runs: [], today: Export.today, calendar: calendar))
        #expect(model.officialCount == 2)
        #expect(model.evidence.contains { $0.role == .duplicate(of: Export.duplicateMarked.id) })
    }

    @Test func differentEffortsSameDayAreNotMerged() {
        let a = PerformanceResult(date: date(31, 10), distance: 3000, time: 15 * 60 + 51, kind: .test)
        let b = PerformanceResult(date: date(31, 10, hour: 18), distance: 5000, time: 28 * 60, kind: .test)
        #expect(RacePerformanceModel.deduplicated([a, b], calendar: calendar).kept.count == 2)
    }

    @Test func fasterTrainingEffortCanRaiseIt() throws {
        let fast = WorkoutSummary(activity: .outdoorRun, start: date(6, 11), duration: 20 * 60, distanceMeters: 4000, averageHeartRate: 175, maxHeartRate: 184, activeEnergyKilocalories: nil, averageCadence: 170, origin: .demo)
        let base = try #require(RacePerformanceModel.assess(results: [Export.test4k], runs: [], maxHeartRate: 185, today: Export.today, calendar: calendar))
        let raised = try #require(RacePerformanceModel.assess(results: [Export.test4k], runs: [fast], maxHeartRate: 185, today: Export.today, calendar: calendar))
        #expect(raised.currentVDOT > base.currentVDOT)
    }

    @Test func treadmillEffortsAreNotCompared() throws {
        let treadmill = WorkoutSummary(activity: .indoorRun, start: date(6, 11), duration: 18 * 60, distanceMeters: 4000, averageHeartRate: 175, maxHeartRate: 184, activeEnergyKilocalories: nil, averageCadence: 170, origin: .demo)
        let model = try #require(RacePerformanceModel.assess(results: [Export.test4k], runs: [treadmill], maxHeartRate: 185, today: Export.today, calendar: calendar))
        #expect(!model.evidence.contains { $0.id == treadmill.id })
    }

    @Test func fewTestsMakeTheTrendProvisionalAndTheRangeWider() throws {
        let one = try #require(RacePerformanceModel.assess(results: [Export.test4k], runs: [], today: Export.today, calendar: calendar))
        #expect(one.trendIsProvisional)
        #expect(!one.hasInterval)
        let two = try #require(RacePerformanceModel.assess(results: [Export.duplicateMarked, Export.test4k], runs: [], today: Export.today, calendar: calendar))
        #expect(two.hasInterval)
        // Dos pruebas casi iguales no dan un rango más estrecho que el mínimo inflado por n efectivo.
        #expect(two.uncertainty >= RacePerformanceModel.minimumUncertainty * (1.5).squareRoot() - 0.01)
    }

    @Test func invalidCadenceAndZeroHeartRateAreFlagged() {
        let zeroHR = WorkoutSummary(activity: .outdoorRun, start: Export.today, duration: 1800, distanceMeters: 6000, averageHeartRate: 0, maxHeartRate: 0, activeEnergyKilocalories: nil, averageCadence: 400, origin: .demo)
        let quality = DataQuality.assess([zeroHR])[zeroHR.id]
        #expect(quality?.heartRateUsable == false)
        #expect(quality?.flags.contains(.implausibleCadence) == true)
        #expect(quality?.usableForPerformance == true)
    }
}
