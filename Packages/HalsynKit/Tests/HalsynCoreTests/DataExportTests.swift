import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}()
private func day(_ d: Int, hour: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))! }

@Suite("Exportar datos en CSV")
struct DataExportTests {
    @Test func dailyRowsUseColumnUnits() {
        let series = [
            MetricSeries(kind: .restingHeartRate, values: [DailyValue(day: day(2), value: 52.4)], origin: .demo),
            MetricSeries(kind: .oxygenSaturation, values: [DailyValue(day: day(2), value: 0.97)], origin: .demo),
            MetricSeries(kind: .walkingRunningDistance, values: [DailyValue(day: day(1), value: 8250)], origin: .demo),
        ]
        let csv = DataExport.dailyCSV(series: series, healthScores: [], recoveryScores: [:], sleep: [], days: [day(2), day(1)], calendar: calendar)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(header.first == "date")
        let first = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let second = lines[2].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(first.count == header.count)
        #expect(first[0] == "2026-11-01")
        #expect(first[header.firstIndex(of: "walk_run_distance_km")!] == "8.25")
        #expect(second[header.firstIndex(of: "resting_hr_bpm")!] == "52")
        #expect(second[header.firstIndex(of: "spo2_pct")!] == "97.0")
        #expect(second[header.firstIndex(of: "hrv_sdnn_ms")!] == "")
    }

    @Test func workoutRowsHavePaceAndMarks() {
        let run = WorkoutSummary(activity: .outdoorRun, start: day(3, hour: 7), duration: 25 * 60, distanceMeters: 5000, averageHeartRate: 158.4, maxHeartRate: 176, activeEnergyKilocalories: 380, averageCadence: 171, origin: .demo)
        let csv = DataExport.workoutsCSV([run], marks: [run.id: "test"], shoes: [run.id: "Pegasus, rojas"], calendar: calendar)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("2026-11-03,07:00,run_outdoor,5.000,25.00,5:00,300,158,176,171,380,"))
        #expect(lines[1].contains(",test,\"Pegasus, rojas\","))
        #expect(lines[1].contains(DataExport.recordID(run.id)))
    }

    @Test func numbersAlwaysUseADot() {
        #expect(DataExport.number(3.14159, digits: 2) == "3.14")
        #expect(DataExport.number(.nan, digits: 1) == "")
        #expect(DataExport.escape("a\"b") == "\"a\"\"b\"")
    }
}
