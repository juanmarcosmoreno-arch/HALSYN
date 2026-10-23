import Foundation
import Testing
@testable import HalsynCore

/// Fecha fija para que los tests no dependan del reloj del sistema.
private let fixedNow: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 23
    components.hour = 12
    return Calendar.halsynGregorian.date(from: components)!
}()

private let english = Locale(identifier: "en_US")

private func makeDemo(seed: UInt64 = 7) -> DemoHealthDataProvider {
    DemoHealthDataProvider(seed: seed, now: { fixedNow })
}

@Suite("Marca")
struct BrandTests {
    @Test func brandNameKeepsSwedishRing() {
        #expect(HalsynBrand.name == "HÅLSYN")
        #expect(HalsynBrand.technicalName == "Halsyn")
    }

    @Test func moduleNamesUseSwedishDiacritics() {
        #expect(HalsynModule.halsa.brandName == "HÄLSA")
        #expect(HalsynModule.mal.brandName == "MÅL")
        #expect(HalsynLexicon.somn.rawValue == "SÖMN")
        #expect(HalsynLexicon.rorelse.rawValue == "RÖRELSE")
    }
}

@Suite("Paleta y contraste")
struct PaletteTests {
    @Test func hexRoundTrip() {
        #expect(HalsynPalette.turquoise.hexString == "#1FB99A")
        #expect(HalsynPalette.darkBackground.hexString == "#081B1A")
    }

    @Test func contrastRatioMatchesWCAGExtremes() {
        let black = HalsynRGBColor(hex: 0x000000), white = HalsynRGBColor(hex: 0xFFFFFF)
        #expect(abs(black.contrastRatio(with: white) - 21) < 0.01)
        #expect(abs(white.contrastRatio(with: white) - 1) < 0.0001)
    }

    @Test(arguments: HalsynColorTokens.textTokens.map(\.name))
    func textTokensMeetWCAGAA(name: String) throws {
        let token = try #require(HalsynColorTokens.textTokens.first { $0.name == name })
        for background in [HalsynColorTokens.background, HalsynColorTokens.surface] {
            let light = token.light.contrastRatio(with: background.light)
            let dark = token.dark.contrastRatio(with: background.dark)
            #expect(light >= 4.5, "\(name) sobre \(background.name) (claro): \(light)")
            #expect(dark >= 4.5, "\(name) sobre \(background.name) (oscuro): \(dark)")
        }
    }

    @Test func brandTurquoiseIsNotUsedAsSmallText() {
        // Documenta por qué existe `accentText`: el turquesa de marca no llega a AA sobre blanco.
        #expect(HalsynPalette.turquoise.contrastRatio(with: HalsynPalette.warmWhite) < 4.5)
    }
}

@Suite("Ritmo y formato")
struct PaceTests {
    @Test func paceFromDistanceAndDuration() throws {
        let pace = try #require(Pace(distanceMeters: 5210, duration: 5210 / 1000 * 282))
        #expect(abs(pace.secondsPerKilometer - 282) < 0.001)
        #expect(pace.formatted() == "4:42")
    }

    @Test func paceFromSpeed() throws {
        let pace = try #require(Pace(metersPerSecond: 1000.0 / 300))
        #expect(pace.formatted() == "5:00")
    }

    @Test func imperialPace() {
        let pace = Pace(secondsPerKilometer: 300)
        #expect(pace.formatted(in: .imperial) == "8:03")
    }

    @Test func invalidInputsProduceNoPace() {
        #expect(Pace(distanceMeters: 0, duration: 100) == nil)
        #expect(Pace(distanceMeters: 5, duration: 100) == nil)
        #expect(Pace(distanceMeters: 1000, duration: 0) == nil)
        #expect(Pace(metersPerSecond: 0) == nil)
        #expect(Pace(metersPerSecond: -1) == nil)
        #expect(Pace(metersPerSecond: 0.1) == nil, "más lento que 60 min/km se trata como parado")
    }

    @Test func fasterPaceSortsFirst() {
        #expect(Pace(secondsPerKilometer: 240) < Pace(secondsPerKilometer: 300))
    }

    @Test func numbersFollowTheRegion() {
        #expect(HalsynFormat.distance(meters: 5210, locale: Locale(identifier: "es_ES")) == "5,21")
        #expect(HalsynFormat.decimal(7.8, fractionDigits: 1, locale: Locale(identifier: "da_DK")) == "7,8")
        #expect(HalsynFormat.integer(8600, locale: english) == "8,600")
        #expect(HalsynFormat.integer(8600, locale: Locale(identifier: "hi_IN")) == "8,600")
        #expect(HalsynFormat.metricValue(0.97, kind: .oxygenSaturation, locale: english) == "97")
    }

    @Test func durationFormatting() {
        #expect(HalsynFormat.duration(59) == "0:59")
        #expect(HalsynFormat.duration(24 * 60 + 36) == "24:36")
        #expect(HalsynFormat.duration(3600 + 5) == "1:00:05")
        #expect(HalsynFormat.duration(-3) == "0:00")
    }

    @Test func distanceAndSleepFormatting() {
        #expect(HalsynFormat.distance(meters: 5210, locale: english) == "5.21")
        #expect(HalsynFormat.distance(meters: 1609.344, unit: .imperial, locale: english) == "1.00")
        #expect(HalsynFormat.hoursAndMinutes(7.8) == (7, 48))
        #expect(HalsynFormat.unitSymbol(for: .walkingRunningDistance, unit: .imperial) == "mi")
        #expect(HalsynFormat.unitSymbol(for: .heartRateVariability) == "ms")
    }
}

@Suite("Disponibilidad de datos")
struct AvailabilityTests {
    @Test func absenceIsNotAValue() {
        #expect(MetricAvailability.noData.reading == nil)
        #expect(MetricAvailability.notAuthorized.reading == nil)
        #expect(MetricAvailability.unsupported.reading == nil)
        #expect(MetricAvailability.noData.statusMessage != MetricAvailability.notAuthorized.statusMessage)
    }

    @Test func scoreIsClampedAndBanded() {
        #expect(DailyScore(day: fixedNow, value: 140, weeklyChange: nil, origin: .demo).value == 100)
        #expect(DailyScore(day: fixedNow, value: -5, weeklyChange: nil, origin: .demo).value == 0)
        #expect(ScoreBand(score: 82) == .good)
        #expect(ScoreBand(score: 39) == .low)
        #expect(ScoreBand(score: 85) == .excellent)
    }

    @Test func goalProgressSaturates() {
        let goal = Goal(title: "x", metric: .steps, target: 8000, current: 12000, period: .daily, origin: .demo)
        #expect(goal.progress == 1)
        #expect(goal.isCompleted)
        let empty = Goal(title: "x", metric: .steps, target: 0, current: 10, period: .daily, origin: .demo)
        #expect(empty.progress == 0)
    }
}

@Suite("Presentación de métricas")
struct MetricDisplayTests {
    @Test func missingDataIsNeverZero() {
        for state in [MetricAvailability.noData, .notAuthorized, .unsupported] {
            let display = MetricDisplay(state, kind: .restingHeartRate)
            #expect(display.value == nil)
            #expect(display.status == state.statusMessage)
            #expect(display.unit == "lpm")
        }
    }

    @Test func availableValuesAreFormatted() {
        let reading = MetricReading(kind: .walkingRunningDistance, value: 5210, date: fixedNow, origin: .demo)
        let display = MetricDisplay(.available(reading), kind: .walkingRunningDistance, locale: english)
        #expect(display.value == "5.21")
        #expect(display.unit == "km")
        #expect(display.origin == .demo)
        let sleep = MetricDisplay(.available(MetricReading(kind: .sleepDuration, value: 7.8, date: fixedNow, origin: .demo)), kind: .sleepDuration, locale: english)
        #expect(sleep.value == "7.8")
        #expect(sleep.unit == "h")
    }
}

@Suite("Proveedor demo")
struct DemoProviderTests {
    @Test func everythingIsLabelledDemo() async {
        let demo = makeDemo()
        #expect(demo.mode == .demo)
        for kind in MetricKind.allCases {
            let reading = await demo.latest(kind, on: fixedNow).reading
            #expect(reading?.origin == .demo)
        }
        #expect(await demo.recentWorkouts(limit: 5).allSatisfy { $0.origin.isDemo })
        #expect(await demo.dailyScore(on: fixedNow)?.origin == .demo)
        #expect(await demo.recoveryScore(on: fixedNow)?.origin == .demo)
        #expect(await demo.goals().allSatisfy { $0.origin.isDemo })
    }

    @Test func valuesAreDeterministicAndOrderIndependent() async {
        let a = makeDemo(), b = makeDemo()
        let seriesA = await a.dailySeries(.heartRateVariability, days: 30, endingOn: fixedNow)
        _ = await b.latest(.steps, on: fixedNow)
        let seriesB = await b.dailySeries(.heartRateVariability, days: 30, endingOn: fixedNow)
        #expect(seriesA == seriesB)
        let workoutsA = await a.recentWorkouts(limit: 6)
        let workoutsB = await b.recentWorkouts(limit: 6)
        #expect(workoutsA == workoutsB)
    }

    @Test func differentSeedsDiffer() async {
        let a = await makeDemo(seed: 1).dailySeries(.steps, days: 14, endingOn: fixedNow)
        let b = await makeDemo(seed: 2).dailySeries(.steps, days: 14, endingOn: fixedNow)
        #expect(a.values != b.values)
    }

    @Test func seriesHasRequestedLengthAndIsChronological() async {
        let series = await makeDemo().dailySeries(.sleepDuration, days: 7, endingOn: fixedNow)
        #expect(series.values.count == 7)
        #expect(zip(series.values, series.values.dropFirst()).allSatisfy { $0.day < $1.day })
        #expect(series.values.last?.day == Calendar.halsynGregorian.startOfDay(for: fixedNow))
    }

    @Test func noDataInTheFuture() async {
        let tomorrow = fixedNow.addingTimeInterval(86_400 * 2)
        #expect(await makeDemo().latest(.steps, on: tomorrow) == .noData)
        #expect(await makeDemo().dailyScore(on: tomorrow) == nil)
    }

    @Test func valuesStayInPlausibleRanges() async {
        let demo = makeDemo()
        let ranges: [MetricKind: ClosedRange<Double>] = [
            .restingHeartRate: 45...65,
            .heartRateVariability: 40...85,
            .sleepDuration: 6...9,
            .steps: 5000...12000,
            .oxygenSaturation: 0.95...0.99,
        ]
        for (kind, range) in ranges {
            let series = await demo.dailySeries(kind, days: 90, endingOn: fixedNow)
            #expect(series.values.allSatisfy { range.contains($0.value) }, "\(kind) fuera de rango")
        }
    }

    @Test func workoutsHaveConsistentDerivedValues() async throws {
        let workouts = await makeDemo().recentWorkouts(limit: 8)
        #expect(workouts.count == 8)
        #expect(zip(workouts, workouts.dropFirst()).allSatisfy { $0.start > $1.start })
        for workout in workouts {
            let pace = try #require(workout.averagePace)
            #expect((285...345).contains(pace.secondsPerKilometer.rounded()))
            #expect((workout.maxHeartRate ?? 0) > (workout.averageHeartRate ?? 0))
        }
        #expect(Set(workouts.map(\.id)).count == workouts.count)
    }

    @Test func demoScoreWithinRange() async throws {
        let score = try #require(await makeDemo().dailyScore(on: fixedNow))
        #expect((0...100).contains(score.value))
        #expect(score.weeklyChange != nil)
    }
}

@Suite("Perfiles de pantalla")
struct WorkoutScreenProfileTests {
    @Test(arguments: WorkoutScreenProfile.defaults)
    func defaultProfilesAreValid(profile: WorkoutScreenProfile) {
        #expect(profile.isValid)
    }

    @Test func invalidProfilesAreDetected() {
        let tooMany = WorkoutScreenProfile(id: "x", name: "x", layout: .two, fields: [.distance, .heartRate, .cadence])
        let repeated = WorkoutScreenProfile(id: "y", name: "y", layout: .two, fields: [.distance, .distance])
        #expect(!tooMany.isValid)
        #expect(!repeated.isValid)
    }

    @Test func demoSampleFillsEveryField() {
        let sample = DemoWorkoutSample()
        for field in WorkoutFieldKind.allCases {
            #expect(sample.value(for: field, locale: english).value != nil, "\(field) sin valor demo")
        }
        #expect(sample.value(for: .elapsedTime).value == "24:36")
        #expect(sample.value(for: .distance, locale: english).value == "5.21")
    }

    @Test func profilesRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(WorkoutScreenProfile.intervals)
        #expect(try JSONDecoder().decode(WorkoutScreenProfile.self, from: data) == .intervals)
    }
}

@Suite("Generador determinista")
struct SeededGeneratorTests {
    @Test func sameSeedSameSequence() {
        var a = SeededRandomNumberGenerator(seed: 42), b = SeededRandomNumberGenerator(seed: 42)
        #expect((0..<10).map { _ in a.next() } == (0..<10).map { _ in b.next() })
    }
}
