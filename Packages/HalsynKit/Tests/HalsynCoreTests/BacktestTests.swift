import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
private let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today)! }

private func test(_ days: Int, vdot: Double, distance: Double = 5000) -> PerformanceResult {
    PerformanceResult(date: daysAgo(days), distance: distance, time: VDOT.raceTime(vdot: vdot, distance: distance), kind: .test)
}

@Suite("Evaluación retrospectiva")
struct BacktestTests {
    @Test func usesOnlyPastData() throws {
        // Forma estable: cada test se predice con los anteriores y el error es ~0.
        let results = [test(120, vdot: 45), test(90, vdot: 45), test(60, vdot: 45), test(30, vdot: 45), test(5, vdot: 45)]
        let backtest = PredictionBacktest.run(results: results, runs: [], maxHeartRate: nil, calendar: calendar)
        // El primero no tiene pasado: no se evalúa.
        #expect(backtest.count == 4)
        #expect(try #require(backtest.meanAbsoluteError) < 1)
        #expect(abs(try #require(backtest.bias)) < 1)
    }

    @Test func futureResultsDoNotLeak() throws {
        // Si el modelo viera el test de hoy (VDOT 55), el de hace 30 días saldría distinto.
        let results = [test(60, vdot: 45), test(30, vdot: 45), test(0, vdot: 55)]
        let backtest = PredictionBacktest.run(results: results, runs: [], maxHeartRate: nil, calendar: calendar)
        let middle = try #require(backtest.cases.first { calendar.isDate($0.date, inSameDayAs: daysAgo(30)) })
        #expect(abs(middle.error) < 1)
        // El último sí falla: mejoraste más de lo que el pasado permitía prever.
        let last = try #require(backtest.cases.last)
        #expect(last.error > 60)
    }

    @Test func metricsAreComputedCorrectly() throws {
        let cases = [
            PredictionBacktest.Case(id: UUID(), date: today, distance: 5000, actual: 1200, predicted: 1230, range: 1180...1280),
            PredictionBacktest.Case(id: UUID(), date: today, distance: 5000, actual: 1200, predicted: 1170, range: 1180...1260),
        ]
        let backtest = PredictionBacktest(cases: cases)
        #expect(backtest.meanAbsoluteError == 30)
        #expect(backtest.rootMeanSquareError == 30)
        #expect(backtest.bias == 0)
        #expect(backtest.coverage == 1)
        #expect(backtest.calibratedRelativeError == nil)
    }

    @Test func calibrationWidensTooNarrowRanges() throws {
        let cases = (0..<6).map { index in
            PredictionBacktest.Case(id: UUID(), date: today, distance: 5000, actual: 1200, predicted: 1200 + (index.isMultiple(of: 2) ? 36 : -36), range: nil)
        }
        let error = try #require(PredictionBacktest(cases: cases).calibratedRelativeError)
        #expect(abs(error - 1.4826 * 0.03) < 0.0001)
        let model = try #require(RacePerformanceModel.assess(results: [test(2, vdot: 45)], runs: [], today: today, calendar: calendar))
        let calibrated = model.predict(5000, calibratedRelativeError: error)
        let range = try #require(calibrated.range)
        #expect(range.upperBound - range.lowerBound > 2 * 1.28 * error * calibrated.time - 0.01)
    }

    @Test func brierNeedsFiveOutcomes() {
        let good = (0..<5).map { GoalOutcome(raceDate: daysAgo($0 * 60), goalTime: 1300, actualTime: $0 < 4 ? 1290 : 1310, modelValue: $0 < 4 ? 0.85 : 0.3) }
        #expect(GoalCalibration.allowsPercentage(good))
        #expect(!GoalCalibration.allowsPercentage(Array(good.prefix(4))))
        let bad = (0..<5).map { GoalOutcome(raceDate: daysAgo($0 * 60), goalTime: 1300, actualTime: 1350, modelValue: 0.9) }
        #expect(!GoalCalibration.allowsPercentage(bad))
    }
}

@Suite("Robustez del motor")
struct EngineRobustnessTests {
    @Test func anEasyRunDoesNotMoveTheModel() throws {
        let base = try #require(RacePerformanceModel.assess(results: [test(10, vdot: 46)], runs: [], maxHeartRate: 186, today: today, calendar: calendar))
        let easy = WorkoutSummary(activity: .outdoorRun, start: daysAgo(1), duration: 3600, distanceMeters: 10_000, averageHeartRate: 135, maxHeartRate: 150, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        let withEasy = try #require(RacePerformanceModel.assess(results: [test(10, vdot: 46)], runs: [easy], maxHeartRate: 186, today: today, calendar: calendar))
        #expect(base.currentVDOT == withEasy.currentVDOT)
    }

    @Test func extremeValuesAreHandled() {
        #expect(VDOT.value(distance: 5000, time: 60) == nil)            // 1 min: fuera del rango del modelo
        #expect(VDOT.value(distance: 0, time: 1200) == nil)
        #expect(VDOT.value(distance: -5000, time: 1200) == nil)
        #expect(DataExport.number(.infinity, digits: 1) == "")
        let absurd = WorkoutSummary(activity: .outdoorRun, start: today, duration: 0, distanceMeters: 1e9, averageHeartRate: 999, maxHeartRate: 1000, activeEnergyKilocalories: nil, averageCadence: 0, origin: .demo)
        let quality = DataQuality.assess([absurd])[absurd.id]
        #expect(quality?.usableForPerformance == false)
        #expect(quality?.heartRateUsable == false)
    }

    @Test func unitsAreConsistent() {
        let pace = Pace(secondsPerKilometer: 300)
        // 5:00/km = 8:03/mi.
        #expect(pace.formatted(in: .imperial) == "8:03")
        #expect(abs(UnitSystem.imperial.metersPerDistanceUnit - 1609.344) < 0.001)
    }

    @Test func oldSettingsStillDecode() throws {
        // Zonas guardadas antes de la FC umbral.
        let json = #"{"method":"heartRateReserve","maxSource":"manual","maxHeartRate":188,"restingHeartRate":52}"#
        let zones = try JSONDecoder().decode(HeartRateZoneConfiguration.self, from: Data(json.utf8))
        #expect(zones.thresholdHeartRate == nil)
        #expect(zones.effectiveMethod == .heartRateReserve)
        // Molestia y actualización en vivo: ida y vuelta.
        let complaint = Complaint(date: today, area: .knee, pain: 12)
        #expect(complaint.pain == 10)
        let decoded = try JSONDecoder().decode(Complaint.self, from: JSONEncoder().encode(complaint))
        #expect(decoded == complaint)
    }
}
