import Foundation
import Testing
@testable import HalsynCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar
}()
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 8))!

private func series(_ kind: MetricKind, base: Double, wobble: Double, today value: Double) -> MetricSeries {
    var values = (1...28).map { offset in
        DailyValue(day: calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))!, value: base + (offset.isMultiple(of: 2) ? wobble : -wobble))
    }
    values.append(DailyValue(day: calendar.startOfDay(for: today), value: value))
    return MetricSeries(kind: kind, values: values.sorted { $0.day < $1.day }, origin: .demo)
}

@Suite("Preparación y señales")
struct ReadinessTests {
    @Test func flagsSeveralStrainedSignals() {
        let history = DailyHistory(series: [
            series(.restingHeartRate, base: 52, wobble: 1, today: 59),
            series(.wristTemperature, base: 36.1, wobble: 0.05, today: 36.6),
            series(.heartRateVariability, base: 60, wobble: 4, today: 58),
            series(.respiratoryRate, base: 14.5, wobble: 0.2, today: 14.6),
        ], calendar: calendar)
        let result = ReadinessEngine().signals(history: history, on: today)
        #expect(Set(result.signals.map(\.metric)) == [.restingHeartRate, .wristTemperature])
        #expect(result.isNotable)
        #expect(result.checked.count == 4)
        #expect(ReadinessEngine.guidance(recovery: 80, signals: result) == .rest)
    }

    @Test func minimumSpreadAvoidsTinyDifferences() {
        // Base muy estable (±0,1 lpm): 2 lpm más no llega a z = 2 con la variación mínima de 2 lpm.
        let history = DailyHistory(series: [series(.restingHeartRate, base: 52, wobble: 0.1, today: 54)], calendar: calendar)
        #expect(ReadinessEngine().signals(history: history, on: today).signals.isEmpty)
    }

    @Test func lowHRVIsASignalHighIsNot() {
        let low = DailyHistory(series: [series(.heartRateVariability, base: 60, wobble: 4, today: 45)], calendar: calendar)
        #expect(ReadinessEngine().signals(history: low, on: today).signals.map(\.metric) == [.heartRateVariability])
        let high = DailyHistory(series: [series(.heartRateVariability, base: 60, wobble: 4, today: 80)], calendar: calendar)
        #expect(ReadinessEngine().signals(history: high, on: today).signals.isEmpty)
    }

    @Test func guidanceFromRecovery() {
        let none = UnusualSignals(day: today, signals: [], checked: [])
        #expect(ReadinessEngine.guidance(recovery: 80, signals: none) == .push)
        #expect(ReadinessEngine.guidance(recovery: 50, signals: none) == .steady)
        #expect(ReadinessEngine.guidance(recovery: 20, signals: none) == .easy)
        #expect(ReadinessEngine.guidance(recovery: nil, signals: none) == .unknown)
        let one = UnusualSignals(day: today, signals: [BodySignal(metric: .restingHeartRate, value: 60, baselineMean: 52, deviation: 3)], checked: [.restingHeartRate])
        #expect(ReadinessEngine.guidance(recovery: 80, signals: one) == .steady)
    }

    @Test func needsBaseline() {
        let short = MetricSeries(kind: .restingHeartRate, values: [DailyValue(day: calendar.startOfDay(for: today), value: 70)], origin: .demo)
        let result = ReadinessEngine().signals(history: DailyHistory(series: [short], calendar: calendar), on: today)
        #expect(result.checked.isEmpty && result.signals.isEmpty)
    }
}
