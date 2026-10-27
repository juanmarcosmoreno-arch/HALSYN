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

private func daysAgo(_ days: Int, hour: Int = 9) -> Date {
    calendar.date(byAdding: .hour, value: hour - 20, to: calendar.date(byAdding: .day, value: -days, to: today)!)!
}

private func workout(_ date: Date, minutes: Double, heartRate: Double?, activity: WorkoutActivity = .outdoorRun) -> WorkoutSummary {
    WorkoutSummary(activity: activity, start: date, duration: minutes * 60, distanceMeters: nil, averageHeartRate: heartRate, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("Carga de entrenamiento")
struct TrainingLoadTests {
    @Test func banisterTRIMPBySex() throws {
        // 60 min a la mitad de la reserva (FC 120 con reposo 60 y máx. 180).
        let male = try #require(BanisterTRIMP.load(duration: 3600, averageHeartRate: 120, restingHeartRate: 60, maxHeartRate: 180, sex: .male))
        #expect(abs(male - 60 * 0.5 * exp(0.96)) < 0.001)
        #expect(abs(male - 78.35) < 0.01)
        let female = try #require(BanisterTRIMP.load(duration: 3600, averageHeartRate: 120, restingHeartRate: 60, maxHeartRate: 180, sex: .female))
        #expect(abs(female - 69.14) < 0.01)
        let unknown = try #require(BanisterTRIMP.load(duration: 3600, averageHeartRate: 120, restingHeartRate: 60, maxHeartRate: 180, sex: nil))
        #expect(abs(unknown - (male + female) / 2) < 0.001)
        // Por encima de la máxima se satura en 1; sin FC media o con datos incoherentes, nada.
        let capped = try #require(BanisterTRIMP.load(duration: 600, averageHeartRate: 200, restingHeartRate: 60, maxHeartRate: 180, sex: .male))
        #expect(abs(capped - 10 * exp(1.92)) < 0.001)
        #expect(BanisterTRIMP.load(duration: 3600, averageHeartRate: nil, restingHeartRate: 60, maxHeartRate: 180, sex: .male) == nil)
        #expect(BanisterTRIMP.load(duration: 3600, averageHeartRate: 120, restingHeartRate: 60, maxHeartRate: 80, sex: .male) == nil)
    }

    @Test func loadsUseTheMaxOfEachSport() {
        let run = workout(daysAgo(1), minutes: 60, heartRate: 150)
        let ride = workout(daysAgo(2), minutes: 60, heartRate: 150, activity: .outdoorRide)
        let noPulse = workout(daysAgo(3), minutes: 40, heartRate: nil)
        let inputs = HeartRateLoadInputs(restingHeartRate: 50, maxHeartRate: [.running: 190, .cycling: 180], sex: .male)
        let result = TrainingLoadCalculator.heartRateLoads([run, ride, noPulse], inputs: inputs)
        #expect(result.loads.count == 2 && result.skipped == 1)
        // A la misma FC, la bici (máx. 180) es relativamente más intensa que correr (máx. 190).
        let runLoad = result.loads.first { $0.sport == .running }!.value
        let rideLoad = result.loads.first { $0.sport == .cycling }!.value
        #expect(rideLoad > runLoad)
        // Sin máxima de bici se usa la de correr; sin FC en reposo no hay carga.
        let fallback = TrainingLoadCalculator.heartRateLoads([ride], inputs: HeartRateLoadInputs(restingHeartRate: 50, maxHeartRate: [.running: 190], sex: .male))
        #expect(abs(fallback.loads[0].value - runLoad) < 0.001)
        #expect(TrainingLoadCalculator.heartRateLoads([run], inputs: HeartRateLoadInputs(restingHeartRate: nil, maxHeartRate: [.running: 190], sex: nil)).skipped == 1)
    }

    @Test func fitnessAndFatigueFollowTheLoad() throws {
        let start = calendar.startOfDay(for: daysAgo(199))
        // 100 al día durante 200 días: la forma y la fatiga tienden a 100.
        let loads = (0..<200).map { WorkoutLoad(workoutID: UUID(), date: daysAgo($0), sport: .running, value: 100) }
        let series = PerformanceModel.series(loads: loads, from: start, through: today, calendar: calendar)
        #expect(series.count == 200)
        #expect(abs(series[0].fitness - 100 / 42) < 0.001)
        #expect(abs(series[0].fatigue - 100 / 7) < 0.001)
        #expect(series[0].form == 0)
        let last = try #require(series.last)
        #expect(last.fitness > 99 && last.fatigue > 99.9)
        #expect(abs(last.form) < 1)
        // Una semana de descanso: la fatiga cae más rápido que la forma y la frescura sube.
        let rested = PerformanceModel.series(loads: loads.filter { $0.date < daysAgo(6, hour: 0) }, from: start, through: today, calendar: calendar)
        let end = try #require(rested.last)
        #expect(end.fatigue < end.fitness && end.form > 20)
    }

    @Test func summaryWeeksAndRollingWindows() throws {
        let loads = [
            WorkoutLoad(workoutID: UUID(), date: daysAgo(0), sport: .running, value: 50),     // jueves (esta semana)
            WorkoutLoad(workoutID: UUID(), date: daysAgo(2), sport: .cycling, value: 80),     // martes
            WorkoutLoad(workoutID: UUID(), date: daysAgo(8), sport: .running, value: 60),     // semana pasada, fuera de los 7 días
            WorkoutLoad(workoutID: UUID(), date: daysAgo(20), sport: .cycling, value: 100),
            WorkoutLoad(workoutID: UUID(), date: daysAgo(40), sport: .running, value: 40),
        ]
        let summary = TrainingLoadBuilder.build(loads: loads, metric: .heartRate, skipped: 2, today: today, calendar: calendar)
        #expect(summary.weeks.count == 12)
        let current = try #require(summary.weeks.last)
        #expect(current.isCurrent && current.total == 130)
        #expect(current.bySport[.cycling] == 80 && current.bySport[.running] == 50)
        #expect(summary.last7Days == 130)
        // Los 28 días anteriores: 60 + 100 → 40 por semana.
        #expect(summary.previousWeeklyAverage == 40)
        #expect(abs((summary.ratio ?? 0) - 3.25) < 0.001)
        #expect(summary.historyDays == 41)
        #expect(summary.isBuildingUp)
        #expect(summary.skipped == 2)
        #expect(summary.points.last.map { calendar.isDate($0.day, inSameDayAs: today) } == true)
        // Sin historia suficiente no hay comparación.
        let short = TrainingLoadBuilder.build(loads: Array(loads.prefix(2)), metric: .heartRate, skipped: 0, today: today, calendar: calendar)
        #expect(short.previousWeeklyAverage == nil && short.ratio == nil)
        let empty = TrainingLoadBuilder.build(loads: [], metric: .power, skipped: 0, today: today, calendar: calendar)
        #expect(empty.points.isEmpty && empty.historyDays == 0 && empty.last7Days == 0)
    }
}
