import Foundation
import Testing
@testable import HalsynCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func workout(_ activity: WorkoutActivity = .outdoorRun, minute: Double = 0, minutes: Double = 30, km: Double? = 6, hr: Double? = 150, maxHR: Double? = 175, cadence: Double? = 168, source: String? = "Apple Watch") -> WorkoutSummary {
    WorkoutSummary(activity: activity, start: base.addingTimeInterval(minute * 60), duration: minutes * 60, distanceMeters: km.map { $0 * 1000 }, averageHeartRate: hr, maxHeartRate: maxHR, activeEnergyKilocalories: nil, averageCadence: cadence, origin: .healthKit(sourceName: source))
}

@Suite("Calidad de datos de Salud")
struct DataQualityTests {
    @Test func duplicatesKeepTheRichestRecord() throws {
        let original = workout()
        let copy = workout(minute: 0.5, minutes: 30.5, km: 6.05, hr: nil, maxHR: nil, cadence: nil, source: "Otra app")
        let quality = DataQuality.assess([original, copy])
        #expect(quality[original.id]?.level == .valid)
        #expect(quality[copy.id]?.flags == [.duplicate(of: original.id)])
        #expect(quality[copy.id]?.level == .excluded)
        #expect(DataQuality.clean([original, copy]).map(\.id) == [original.id])
    }

    @Test func overlappingRecordsFromAnotherSourceAreFlagged() throws {
        let watch = workout(minutes: 40, km: 8)
        let phone = workout(minute: 5, minutes: 30, km: 6, hr: nil, maxHR: nil, cadence: nil, source: "Strava")
        let quality = DataQuality.assess([watch, phone])
        #expect(quality[phone.id]?.flags == [.overlaps(watch.id, otherSource: true)])
        #expect(quality[watch.id]?.flags.isEmpty == true)
    }

    @Test func differentSportsOrSeparateRunsAreNotDuplicates() {
        let run = workout()
        let walk = workout(.walk, minute: 1, minutes: 30, km: 3)
        let later = workout(minute: 120)
        let quality = DataQuality.assess([run, walk, later])
        #expect(quality.values.allSatisfy { !$0.flags.contains(where: \.removesWorkout) })
    }

    @Test func impossibleValuesAreDoubtfulNotDeleted() {
        let noDistance = workout(km: nil)
        let gpsGlitch = workout(minute: 100, minutes: 10, km: 8)      // 1:15/km
        let badHR = workout(minute: 200, hr: 250, maxHR: 260)
        let zeroCadence = workout(minute: 300, cadence: 0)
        let tiny = workout(minute: 400, minutes: 1, km: 0.15)
        let quality = DataQuality.assess([noDistance, gpsGlitch, badHR, zeroCadence, tiny])
        #expect(quality[noDistance.id]?.flags.contains(.missingDistance) == true)
        #expect(quality[gpsGlitch.id]?.flags.contains(.implausiblePace) == true)
        #expect(quality[gpsGlitch.id]?.usableForPerformance == false)
        #expect(quality[badHR.id]?.heartRateUsable == false)
        #expect(quality[badHR.id]?.usableForPerformance == true)
        #expect(quality[zeroCadence.id]?.flags == [.zeroCadence])
        #expect(quality[zeroCadence.id]?.needsReview == false)
        #expect(quality[tiny.id]?.flags.contains(.tooShort) == true)
        // Nada se borra: solo los duplicados salen de la lista limpia.
        #expect(DataQuality.clean([noDistance, gpsGlitch, badHR, zeroCadence, tiny]).count == 5)
        #expect(DataQuality.forPerformance([noDistance, gpsGlitch, badHR, zeroCadence, tiny]).count == 2)
    }

    @Test func userOverridesWin() {
        let original = workout()
        let copy = workout(minute: 0.2, hr: nil)
        #expect(DataQuality.clean([original, copy], excluded: [original.id], included: [copy.id]).map(\.id) == [copy.id])
    }
}

@Suite("Tipo de esfuerzo")
struct EffortClassifierTests {
    @Test func classifiesByHeartRateFraction() {
        #expect(EffortClassifier.classify(workout(hr: 140), maxHeartRate: 190) == .easy)
        #expect(EffortClassifier.classify(workout(hr: 160), maxHeartRate: 190) == .moderate)
        #expect(EffortClassifier.classify(workout(hr: 168), maxHeartRate: 190) == .hard)
        #expect(EffortClassifier.classify(workout(minutes: 22, km: 5, hr: 175), maxHeartRate: 190) == .maximal)
        // Muy largo para ser una prueba a tope aunque el pulso sea alto.
        #expect(EffortClassifier.classify(workout(minutes: 100, km: 20, hr: 175), maxHeartRate: 190) == .hard)
        #expect(EffortClassifier.classify(workout(hr: nil), maxHeartRate: 190) == .unknown)
        #expect(EffortClassifier.classify(workout(), maxHeartRate: nil) == .unknown)
        #expect(EffortClassifier.classify(workout(hr: 120), maxHeartRate: 190, marked: .race) == .race)
    }

    @Test func referenceMaxIgnoresASingleSpike() {
        let runs = [workout(maxHR: 228)] + (1...5).map { workout(minute: Double($0) * 100, maxHR: 186 - Double($0)) }
        #expect(EffortClassifier.referenceMaxHeartRate(configured: nil, runs: runs) == 185)
        #expect(EffortClassifier.referenceMaxHeartRate(configured: 192, runs: runs) == 192)
    }
}
