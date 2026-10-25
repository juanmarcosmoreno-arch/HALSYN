import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    calendar.firstWeekday = 2
    return calendar
}()
/// Jueves 22 de octubre de 2026, 20:00.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 20))!

private func day(_ offset: Int, hour: Int = 8) -> Date {
    calendar.date(byAdding: .hour, value: hour - 20, to: calendar.date(byAdding: .day, value: -offset, to: today)!)!
}

private func run(_ date: Date, km: Double, minutesPerKm: Double, heartRate: Double? = nil, activity: WorkoutActivity = .outdoorRun) -> WorkoutSummary {
    WorkoutSummary(activity: activity, start: date, duration: km * minutesPerKm * 60, distanceMeters: km * 1000, averageHeartRate: heartRate, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("SPRING · estadísticas")
struct RunningStatsTests {
    let runs = [
        run(day(1), km: 10, minutesPerKm: 6, heartRate: 150),   // miércoles
        run(day(3), km: 5, minutesPerKm: 5, heartRate: 160),    // lunes
        run(day(8), km: 8, minutesPerKm: 5.5),                  // miércoles pasado
        run(day(5), km: 21, minutesPerKm: 6.2),                 // sábado pasado (después del punto equivalente)
        run(day(2), km: 4, minutesPerKm: 9, activity: .walk),   // caminata: no cuenta
    ]

    @Test func weekTotalsAndFairComparison() throws {
        let stats = RunningStatsBuilder.build(runs: runs, period: .week, today: today, calendar: calendar)
        #expect(stats.current.count == 2)
        #expect(stats.current.distance == 15_000)
        // Ritmo medio ponderado: (60 + 25) min / 15 km.
        #expect(abs((stats.current.averagePace?.secondsPerKilometer ?? 0) - 340) < 0.5)
        // FC media ponderada por duración: (150·60 + 160·25) / 85.
        #expect(abs((stats.current.averageHeartRate ?? 0) - 152.94) < 0.01)
        // La semana pasada hasta el jueves a la misma hora: solo la del miércoles.
        #expect(stats.previousToDate.count == 1 && stats.previousToDate.distance == 8000)
    }

    @Test func bucketsEndWithTheCurrentOne() {
        let week = RunningStatsBuilder.build(runs: runs, period: .week, today: today, calendar: calendar)
        #expect(week.buckets.count == 12)
        #expect(week.buckets.last?.isCurrent == true && week.buckets.last?.distance == 15_000)
        #expect(week.buckets[10].distance == 29_000)
        let year = RunningStatsBuilder.build(runs: runs, period: .year, today: today, calendar: calendar)
        #expect(year.buckets.count == 12)
        #expect(year.buckets.last?.distance == 44_000)
    }

    @Test func records() throws {
        let stats = RunningStatsBuilder.build(runs: runs, period: .month, today: today, calendar: calendar)
        #expect(stats.records.longest?.distanceMeters == 21_000)
        // El de 5 km a 5:00 es el más rápido de 5 km o más.
        #expect(stats.records.fastest?.distanceMeters == 5000)
        #expect(stats.records.biggestWeek?.distance == 29_000)
    }

    @Test func emptyIsZero() {
        let stats = RunningStatsBuilder.build(runs: [], period: .week, today: today, calendar: calendar)
        #expect(stats.current.count == 0 && stats.current.averagePace == nil && stats.records.longest == nil)
    }
}
