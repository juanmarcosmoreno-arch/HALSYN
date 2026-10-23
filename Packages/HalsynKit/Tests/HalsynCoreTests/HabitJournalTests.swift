import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}()

private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!

private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!
}

@Suite("Diario de hábitos")
struct HabitJournalTests {
    @Test func storageAndStreak() throws {
        var journal = HabitJournal()
        journal.set([.alcohol], on: day(-1), calendar: calendar)
        journal.set([], on: day(-2), calendar: calendar)
        journal.set([.stress, .nap], on: day(-4), calendar: calendar)
        #expect(journal.isLogged(day(-2), calendar: calendar))
        #expect(!journal.isLogged(day(-3), calendar: calendar))
        // Hoy sin registrar: la racha cuenta desde ayer.
        #expect(journal.streak(endingOn: today, calendar: calendar) == 2)
        let defaults = try #require(UserDefaults(suiteName: "journal-\(UUID().uuidString)"))
        HabitJournalStorage.save(journal, to: defaults)
        #expect(HabitJournalStorage.load(from: defaults) == journal)
    }

    @Test func detectsLowerHRVAfterTaggedDays() {
        var journal = HabitJournal()
        var hrv: [DailyValue] = []
        var sleep: [DailyValue] = []
        for offset in 1...60 {
            let tagged = offset % 4 == 0
            journal.set(tagged ? [.alcohol] : [], on: day(-offset), calendar: calendar)
            // Métrica del día siguiente: HRV 10 ms más baja tras la etiqueta, con algo de ruido.
            let noise = Double((offset * 7) % 5) - 2
            hrv.append(DailyValue(day: day(-offset + 1), value: (tagged ? 50 : 60) + noise))
            sleep.append(DailyValue(day: day(-offset + 1), value: 7.2 + noise / 10))
        }
        let history = DailyHistory(series: [
            MetricSeries(kind: .heartRateVariability, values: hrv.sorted { $0.day < $1.day }, origin: .demo),
            MetricSeries(kind: .sleepDuration, values: sleep.sorted { $0.day < $1.day }, origin: .demo),
        ], calendar: calendar)
        let report = HabitImpactEngine().analyze(journal: journal, history: history, endingOn: today)
        #expect(report.loggedDays == 60)
        let impact = report.impacts.first { $0.tag == .alcohol && $0.metric == .heartRateVariability }
        #expect(impact != nil)
        #expect(impact?.isFavorable == false)
        #expect(abs((impact?.difference ?? 0) + 10) < 1)
        // El sueño no cambia: no aparece.
        #expect(!report.impacts.contains { $0.metric == .sleepDuration })
        #expect(report.progress.first?.isReady == true)
    }

    @Test func needsFiveDaysWithAndWithout() {
        var journal = HabitJournal()
        for offset in 1...4 { journal.set([.sauna], on: day(-offset), calendar: calendar) }
        for offset in 5...20 { journal.set([], on: day(-offset), calendar: calendar) }
        let report = HabitImpactEngine().analyze(journal: journal, history: DailyHistory(series: [], calendar: calendar), endingOn: today)
        #expect(report.impacts.isEmpty)
        #expect(report.progress == [HabitProgress(tag: .sauna, withCount: 4, withoutCount: 16, need: 5)])
    }

    @Test func demoJournalShowsAPattern() async {
        let provider = DemoHealthDataProvider(calendar: calendar, now: { today })
        let journal = DemoHabitJournal.make(endingOn: today, calendar: calendar)
        let report = await provider.habitReport(journal: journal, endingOn: today, calendar: calendar)
        #expect(report.impacts.contains { $0.tag == .alcohol })
    }
}


@Suite("Cuerpo")
struct BodyMetricsTests {
    @Test func bodyMassIndex() {
        #expect(abs((BodyMetrics.bodyMassIndex(weightKilograms: 74.5, heightMeters: 1.78) ?? 0) - 23.51) < 0.01)
        #expect(BodyMetrics.bodyMassIndex(weightKilograms: 74.5, heightMeters: 0) == nil)
    }

    @Test func monthlyChangeNeedsBothWindows() {
        let recent = (0..<7).map { DailyValue(day: day(-$0), value: 74) }
        let earlier = (28...35).map { DailyValue(day: day(-$0), value: 75) }
        #expect(BodyMetrics.monthlyChange(recent + earlier, endingOn: today, calendar: calendar) == -1)
        #expect(BodyMetrics.monthlyChange(recent, endingOn: today, calendar: calendar) == nil)
    }

    @Test func bodyValuesFormatInUnits() {
        let reading = MetricReading(kind: .bodyMass, value: 74.5, date: today, origin: .demo)
        let english = Locale(identifier: "en_US")
        #expect(MetricDisplay(.available(reading), kind: .bodyMass, unitSystem: .metric, locale: english).value == "74.5")
        let pounds = MetricDisplay(.available(reading), kind: .bodyMass, unitSystem: .imperial, locale: english)
        #expect(pounds.value == "164.2" && pounds.unit == "lb")
        let fat = MetricDisplay(.available(MetricReading(kind: .bodyFatPercentage, value: 0.182, date: today, origin: .demo)), kind: .bodyFatPercentage, locale: english)
        #expect(fat.value == "18.2" && fat.unit == "%")
    }
}
