import Foundation
import Testing
@testable import HalsynCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private let lastDay = utc.date(from: DateComponents(year: 2026, month: 10, day: 24))!

private func day(_ offset: Int) -> Date { utc.date(byAdding: .day, value: -offset, to: lastDay)! }

/// Serie de `count` días que terminan en `lastDay` (0 = último día).
private func series(_ kind: MetricKind, _ value: (Int) -> Double, count: Int = 35) -> MetricSeries {
    MetricSeries(kind: kind, values: (0..<count).map { DailyValue(day: day($0), value: value($0)) }, origin: .demo)
}

private func run(_ offset: Int, km: Double) -> WorkoutSummary {
    WorkoutSummary(activity: .outdoorRun, start: day(offset).addingTimeInterval(8 * 3600), duration: km * 330, distanceMeters: km * 1000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("Resumen semanal")
struct WeeklyReviewTests {
    @Test func comparesTheWeekWithTheFourBefore() throws {
        let history = DailyHistory(series: [
            // Esta semana 7 h; antes 7,5 h.
            series(.sleepDuration) { $0 < 7 ? 7 : 7.5 },
            // FC en reposo: 55 esta semana, 52 antes.
            series(.restingHeartRate) { $0 < 7 ? 55 : 52 },
            // Pasos sin cambios.
            series(.steps) { _ in 9000 },
            // 30 min de ejercicio cada día esta semana; 10 antes.
            series(.exerciseTime) { $0 < 7 ? 30 : 10 },
        ], calendar: utc)
        let runs = [run(1, km: 10), run(3, km: 8), run(10, km: 5), run(20, km: 5)]
        let review = WeeklyReviewBuilder.build(history: history, runs: runs, scores: [], endingOn: lastDay)

        #expect(review.start == day(6))
        #expect(review.end == lastDay)
        let sleep = try #require(review.fact(.sleep))
        #expect(sleep.value == 7 && sleep.baseline == 7.5)
        #expect(sleep.trend == .down)
        #expect(review.fact(.restingHeartRate)?.trend == .up)
        #expect(review.fact(.steps)?.trend == .similar)
        let exercise = try #require(review.fact(.exercise))
        #expect(exercise.value == 210 && exercise.baseline == 70)
        let running = try #require(review.fact(.running))
        #expect(running.count == 2 && running.value == 18_000 && running.baseline == 2500)
        // Sin HRV ni puntuación: no se inventan.
        #expect(review.fact(.heartRateVariability) == nil)
        #expect(review.fact(.score) == nil)
    }

    @Test func needsEnoughDays() {
        let history = DailyHistory(series: [series(.sleepDuration, { _ in 7 }, count: 3)], calendar: utc)
        let review = WeeklyReviewBuilder.build(history: history, runs: [], scores: [], endingOn: lastDay)
        #expect(review.facts.isEmpty)
    }

    @Test func baselineNeedsTwoWeeksOfData() throws {
        let history = DailyHistory(series: [series(.steps, { _ in 8000 }, count: 12)], calendar: utc)
        let review = WeeklyReviewBuilder.build(history: history, runs: [], scores: [], endingOn: lastDay)
        let steps = try #require(review.fact(.steps))
        #expect(steps.baseline == nil)
        #expect(steps.trend == nil)
    }
}

@Suite("Validador de texto generado")
struct GeneratedTextValidatorTests {
    let facts = ["Dormiste 7,5 h de media por noche (7 h 10 min en las 4 semanas anteriores).", "Caminaste 8.432 pasos al día."]

    @Test func acceptsNumbersFromTheFacts() {
        #expect(GeneratedTextValidator.validate("Esta semana dormiste 7.5 h y caminaste 8,432 pasos al día. ¡Bien!", allowedSources: facts) == nil)
    }

    @Test func rejectsInventedNumbers() {
        #expect(GeneratedTextValidator.validate("Dormiste 6 horas y media.", allowedSources: facts) == .unknownNumber("6"))
        #expect(GeneratedTextValidator.validate("Tu FC subió 3 lpm.", allowedSources: facts) == .unknownNumber("3"))
    }

    @Test func rejectsClinicalTerms() {
        #expect(GeneratedTextValidator.validate("Podría ser una enfermedad.", allowedSources: facts) == .clinicalTerm("enfermedad"))
        #expect(GeneratedTextValidator.validate("No es un diagnóstico.", allowedSources: facts) == .clinicalTerm("diagnóstic"))
        #expect(GeneratedTextValidator.validate("This is not a diagnosis.", allowedSources: facts) == .clinicalTerm("diagnos"))
    }

    @Test func rejectsEmptyAndLongText() {
        #expect(GeneratedTextValidator.validate("  ", allowedSources: facts) == .empty)
        #expect(GeneratedTextValidator.validate(String(repeating: "a", count: 1000), allowedSources: facts) == .tooLong)
    }

    @Test func extractsNumbersAcrossScripts() {
        #expect(GeneratedTextValidator.numbers(in: "7,5 h · 8.432 pasos · 6:45 · ७५") == ["75", "8432", "645", "75"])
        // Un punto final no es parte del número.
        #expect(GeneratedTextValidator.numbers(in: "Fueron 12.") == ["12"])
    }
}
