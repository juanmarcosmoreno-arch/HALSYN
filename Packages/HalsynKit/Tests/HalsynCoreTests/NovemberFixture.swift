import Foundation
@testable import HalsynCore

/// Carreras de la exportación del 7/11/2026 (anonimizadas: sin zapatillas ni
/// identificadores). Columnas: fecha, hora, tipo, km, minutos, FC media, FC máx., cadencia, desnivel.
enum NovemberFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static let csv = """
    2026-06-22,17:47,run_treadmill,1.208,7.15,171,177,156,
    2026-06-22,18:28,run_treadmill,0.688,4.12,175,175,158,
    2026-06-23,19:30,run_treadmill,0.178,4.65,94,158,38,
    2026-06-23,19:35,run_treadmill,4.627,26.14,172,189,160,
    2026-06-29,17:47,run_treadmill,3.003,17.22,174,180,159,
    2026-07-11,17:24,run_outdoor,1.327,8.25,154,178,146,2
    2026-07-14,19:16,run_treadmill,4.691,30.28,168,185,147,
    2026-07-16,19:46,run_treadmill,3.805,22.07,175,185,158,
    2026-07-20,18:39,run_treadmill,1.940,16.18,152,184,123,
    2026-07-22,14:25,run_treadmill,5.670,37.55,157,175,152,
    2026-07-23,18:59,run_treadmill,7.236,47.18,162,183,151,
    2026-07-27,17:25,run_treadmill,4.237,26.14,163,173,156,
    2026-07-28,19:01,run_treadmill,6.510,42.14,157,182,155,
    2026-08-05,18:50,run_treadmill,0.753,5.06,158,166,161,
    2026-08-07,18:11,run_treadmill,0.390,3.18,114,124,140,
    2026-08-10,17:57,run_treadmill,4.017,25.34,166,177,159,
    2026-08-20,19:11,run_treadmill,5.076,34.15,166,181,155,
    2026-08-26,18:03,run_treadmill,1.766,11.55,158,162,154,
    2026-08-27,19:07,run_treadmill,5.030,34.44,174,186,155,
    2026-09-01,19:08,run_treadmill,5.112,33.88,165,186,157,
    2026-09-02,18:02,run_treadmill,2.054,12.14,168,176,161,
    2026-09-10,16:25,run_outdoor,2.545,14.00,170,179,159,1
    2026-09-10,16:46,run_outdoor,1.165,6.90,168,179,161,6
    2026-09-11,18:36,run_treadmill,3.006,20.18,157,164,160,
    2026-09-16,17:59,run_treadmill,0.496,4.03,143,151,140,
    2026-09-18,18:13,run_treadmill,2.534,17.60,156,173,156,
    2026-09-19,15:55,run_outdoor,1.095,6.47,172,177,165,1
    2026-09-23,17:53,run_treadmill,3.274,20.70,158,177,161,
    2026-09-25,17:55,run_treadmill,3.108,20.57,161,167,160,
    2026-09-26,07:54,run_outdoor,2.017,10.38,170,174,164,2
    2026-10-01,19:06,run_treadmill,3.917,27.96,159,177,151,
    2026-10-06,18:24,run_treadmill,4.618,32.45,163,177,151,
    2026-10-09,18:10,run_treadmill,3.993,26.65,164,177,156,
    2026-10-23,07:49,run_outdoor,,9.05,72,79,,
    2026-10-23,17:54,run_outdoor,0.581,3.05,149,167,150,
    2026-10-23,18:02,run_outdoor,0.904,5.34,154,173,152,
    2026-10-23,18:20,run_outdoor,0.535,2.99,156,172,146,
    2026-10-23,19:03,run_treadmill,0.969,11.72,143,176,87,
    2026-10-28,18:11,run_outdoor,0.268,1.33,0,0,157,
    2026-10-28,18:23,run_outdoor,0.978,5.59,166,173,153,10
    2026-10-28,18:53,run_outdoor,0.487,2.77,151,166,156,
    2026-10-29,18:09,run_outdoor,2.040,10.96,160,171,161,
    2026-10-31,18:41,run_outdoor,3.026,15.85,176,182,163,10
    2026-10-31,19:03,run_outdoor,0.720,4.26,161,174,162,3
    2026-11-01,06:58,run_outdoor,4.005,22.41,170,182,167,3
    2026-11-02,18:21,run_outdoor,4.005,22.10,171,185,161,3
    2026-11-04,05:57,run_outdoor,5.025,32.22,161,180,162,13
    2026-11-06,18:10,run_outdoor,3.035,17.34,166,181,159,65
    2026-11-07,09:31,run_outdoor,6.024,36.85,166,180,162,27
    """

    /// Ids estables (derivados de la fecha y la hora) para poder referirse a cada carrera.
    static let runs: [WorkoutSummary] = csv.split(separator: "\n").compactMap { line in
        let cells = line.trimmingCharacters(in: .whitespaces).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard cells.count >= 9 else { return nil }
        let day = cells[0].split(separator: "-").compactMap { Int($0) }
        let time = cells[1].split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, time.count == 2,
              let start = calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1])),
              let minutes = Double(cells[4]) else { return nil }
        let seed = String(format: "%04d%02d%02d%02d%02d", day[0], day[1], day[2], time[0], time[1])
        let id = UUID(uuidString: "00000000-0000-0000-0000-" + String(repeating: "0", count: 12 - seed.count) + seed) ?? UUID()
        let km = Double(cells[3])
        let distance: Double? = km.map { value in value * 1000 }
        let duration: TimeInterval = minutes * 60
        return WorkoutSummary(
            id: id,
            activity: cells[2] == "run_outdoor" ? .outdoorRun : .indoorRun,
            start: start,
            duration: duration,
            distanceMeters: distance,
            averageHeartRate: Double(cells[5]),
            maxHeartRate: Double(cells[6]),
            activeEnergyKilocalories: nil,
            averageCadence: Double(cells[7]),
            origin: .healthKit(sourceName: "Apple Watch"),
            elevationGain: Double(cells[8])
        )
    }

    static func run(_ month: Int, _ day: Int, _ hour: Int) -> WorkoutSummary {
        runs.first { calendar.component(.month, from: $0.start) == month && calendar.component(.day, from: $0.start) == day && calendar.component(.hour, from: $0.start) == hour }!
    }

    static let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 21))!
}
