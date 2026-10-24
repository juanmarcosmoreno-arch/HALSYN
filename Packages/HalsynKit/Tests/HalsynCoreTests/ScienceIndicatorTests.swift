import Foundation
import Testing
@testable import HalsynCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private let firstDay = utc.date(from: DateComponents(year: 2026, month: 3, day: 1))!

/// Noche que termina el día `index`: de `bed` (hora del día anterior, puede
/// pasar de 24) a `wake` (hora del día).
private func night(_ index: Int, bed: Double, wake: Double) -> SleepNight {
    let day = utc.date(byAdding: .day, value: index, to: firstDay)!
    let start = day.addingTimeInterval((bed - 24) * 3600)
    let end = day.addingTimeInterval(wake * 3600)
    let segment = SleepSegment(start: start, end: end, stage: .asleepCore)
    return SleepNight(day: day, asleep: end.timeIntervalSince(start), sleepStart: start, sleepEnd: end, awake: 0, stages: [.asleepCore: end.timeIntervalSince(start)], segments: [segment], sourceName: nil, origin: .demo)
}

@Suite("Life's Essential 8")
struct CardiovascularHealthTests {
    @Test func tablesMatchThePublishedBands() {
        #expect(CardiovascularHealthEngine.activityPoints(150) == 100)
        #expect(CardiovascularHealthEngine.activityPoints(149) == 90)
        #expect(CardiovascularHealthEngine.activityPoints(45) == 40)
        #expect(CardiovascularHealthEngine.activityPoints(0) == 0)
        #expect(CardiovascularHealthEngine.sleepPoints(7.5) == 100)
        #expect(CardiovascularHealthEngine.sleepPoints(6.5) == 70)
        #expect(CardiovascularHealthEngine.sleepPoints(9.5) == 90)
        #expect(CardiovascularHealthEngine.sleepPoints(10.5) == 40)
        #expect(CardiovascularHealthEngine.sleepPoints(3) == 0)
        #expect(CardiovascularHealthEngine.bodyMassIndexPoints(24.9) == 100)
        #expect(CardiovascularHealthEngine.bodyMassIndexPoints(27) == 70)
        #expect(CardiovascularHealthEngine.bodyMassIndexPoints(36) == 15)
        #expect(CardiovascularHealthEngine.bloodPressurePoints(systolic: 118, diastolic: 76, treated: false) == 100)
        #expect(CardiovascularHealthEngine.bloodPressurePoints(systolic: 125, diastolic: 78, treated: false) == 75)
        #expect(CardiovascularHealthEngine.bloodPressurePoints(systolic: 118, diastolic: 84, treated: false) == 50)
        #expect(CardiovascularHealthEngine.bloodPressurePoints(systolic: 145, diastolic: 85, treated: true) == 5)
        #expect(CardiovascularHealthEngine.lipidPoints(nonHDL: 129, treated: false) == 100)
        #expect(CardiovascularHealthEngine.lipidPoints(nonHDL: 150, treated: true) == 40)
        #expect(CardiovascularHealthEngine.nicotinePoints(.init(status: .quitOneToFiveYears, secondhandAtHome: true)) == 30)
        #expect(CardiovascularHealthEngine.nicotinePoints(.init(status: .currentSmoking, secondhandAtHome: true)) == 0)
        #expect(CardiovascularHealthEngine.glucosePoints(.init(hasDiabetes: false, fastingGlucose: 92, hbA1c: nil, date: firstDay)) == 100)
        #expect(CardiovascularHealthEngine.glucosePoints(.init(hasDiabetes: true, fastingGlucose: nil, hbA1c: 7.4, date: firstDay)) == 30)
        #expect(CardiovascularHealthEngine.glucosePoints(.init(hasDiabetes: true, fastingGlucose: 110, hbA1c: nil, date: firstDay)) == nil)
    }

    @Test func compositeIsTheMeanOfAvailableComponents() {
        let measurements = CardioHealthMeasurements(weeklyActivityMinutes: 160, averageSleepHours: 6.5, bodyMassIndex: 26)
        let partial = CardiovascularHealthEngine.evaluate(measurements: measurements, inputs: CardioHealthInputs())
        // Solo 3 componentes: no hay puntuación global.
        #expect(partial.score == nil)
        #expect(partial.available.count == 3)

        let inputs = CardioHealthInputs(nicotine: .init(status: .never, secondhandAtHome: false))
        let result = CardiovascularHealthEngine.evaluate(measurements: measurements, inputs: inputs)
        #expect(result.score == 85) // (100 + 70 + 70 + 100) / 4
        #expect(result.level == .high)
        #expect(!result.isComplete)
        #expect(result.components.first { $0.component == .diet }?.points == nil)
    }
}

@Suite("Regularidad del sueño")
struct SleepRegularityIndexTests {
    @Test func identicalScheduleScoresOneHundred() throws {
        let nights = (0..<7).map { night($0, bed: 23, wake: 7) }
        let index = try #require(SleepRegularityIndex.compute(nights, calendar: utc))
        #expect(index.pairs == 6)
        #expect(abs(index.value - 100) < 0.01)
    }

    @Test func shiftedScheduleLowersTheIndex() throws {
        // Días alternos con 2 h de diferencia: 4 h de 24 no coinciden.
        let nights = (0..<7).map { $0.isMultiple(of: 2) ? night($0, bed: 23, wake: 7) : night($0, bed: 25, wake: 9) }
        let index = try #require(SleepRegularityIndex.compute(nights, calendar: utc))
        #expect(abs(index.value - (200 * 20.0 / 24 - 100)) < 0.01)
    }

    @Test func needsConsecutiveNights() {
        let nights = [0, 2, 4, 6, 8, 10].map { night($0, bed: 23, wake: 7) }
        #expect(SleepRegularityIndex.compute(nights, calendar: utc) == nil)
    }
}

@Suite("Pasos por edad")
struct StepsReferenceTests {
    @Test func referenceFollowsPaluch() {
        #expect(HealthScoreConfiguration.stepsReference(age: 35) == 9000)
        #expect(HealthScoreConfiguration.stepsReference(age: 65) == 7000)
        #expect(HealthScoreConfiguration.stepsReference(age: nil) == 8000)
    }
}

@Suite("Cuestionario MEPA")
struct MEPATests {
    private func answers(_ values: [MEPAItem: Double]) -> DietAnswers {
        var all = Dictionary(uniqueKeysWithValues: MEPAItem.allCases.map { ($0, 0.0) })
        all.merge(values) { _, new in new }
        return DietAnswers(servingsPerWeek: all, date: firstDay)
    }

    @Test func criteriaFollowTableC() {
        // Todo a 0: suman los límites "menos de" (carne, pollo, queso, mantequilla, dulces, comida rápida).
        #expect(answers([:]).score(sex: .male) == 6)
        let healthy = answers([.oliveOil: 21, .leafyGreens: 8, .otherVegetables: 21, .berries: 3, .otherFruit: 14, .fish: 2, .beans: 4, .wholeGrains: 28, .nuts: 5, .alcohol: 5])
        #expect(healthy.score(sex: .male) == 16)
        #expect(healthy.score(sex: .female) == 16)
        // 10 bebidas a la semana: moderado en hombres, no en mujeres ni con sexo desconocido.
        let drinks = answers([.alcohol: 10])
        #expect(drinks.score(sex: .male) == 7)
        #expect(drinks.score(sex: nil) == 6)
        // Límites estrictos: exactamente 2 al día de aceite no suma.
        #expect(answers([.oliveOil: 14]).score(sex: .male) == 6)
    }

    @Test func incompleteAnswersGiveNoScore() {
        var partial = answers([:])
        partial.servingsPerWeek[.nuts] = nil
        #expect(partial.score(sex: .male) == nil)
    }

    @Test func mepaMapsToDietPoints() {
        #expect(CardiovascularHealthEngine.dietPoints(16) == 100)
        #expect(CardiovascularHealthEngine.dietPoints(13) == 80)
        #expect(CardiovascularHealthEngine.dietPoints(8) == 50)
        #expect(CardiovascularHealthEngine.dietPoints(5) == 25)
        #expect(CardiovascularHealthEngine.dietPoints(3) == 0)
        let inputs = CardioHealthInputs(diet: answers([.oliveOil: 21]))
        let result = CardiovascularHealthEngine.evaluate(measurements: CardioHealthMeasurements(), inputs: inputs, sex: .male)
        #expect(result.components.first { $0.component == .diet }?.points == 25) // MEPA 7
    }
}
