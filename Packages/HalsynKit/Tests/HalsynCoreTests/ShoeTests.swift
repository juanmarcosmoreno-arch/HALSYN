import Foundation
import Testing
@testable import HalsynCore

private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func workout(_ daysAfter: Double, km: Double, activity: WorkoutActivity = .outdoorRun) -> WorkoutSummary {
    WorkoutSummary(activity: activity, start: base.addingTimeInterval(daysAfter * 86_400), duration: km * 330, distanceMeters: km * 1000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
}

@Suite("Zapatillas")
struct ShoeTests {
    @Test func defaultShoeCollectsRunsAfterItsStart() {
        var closet = ShoeCloset()
        let pegasus = Shoe(name: "Pegasus", startDate: base.addingTimeInterval(86_400), initialDistance: 50_000)
        closet.upsert(pegasus)
        #expect(closet.defaultShoeID == pegasus.id)
        let runs = [workout(0, km: 10), workout(2, km: 8), workout(3, km: 12), workout(4, km: 5, activity: .walk)]
        // La de antes de la fecha de alta y la caminata no cuentan.
        #expect(closet.distance(of: pegasus, workouts: runs) == 70_000)
        #expect(closet.runs(of: pegasus, workouts: runs) == 2)
        #expect(abs(closet.wear(of: pegasus, workouts: runs) - 0.1) < 0.0001)
    }

    @Test func manualAssignmentWins() {
        var closet = ShoeCloset()
        let daily = Shoe(name: "Diarias", startDate: base)
        let race = Shoe(name: "Carreras", startDate: base)
        closet.upsert(daily)
        closet.upsert(race)
        let runs = [workout(1, km: 10), workout(2, km: 21)]
        closet.assign(runs[1].id, to: race.id)
        #expect(closet.distance(of: daily, workouts: runs) == 10_000)
        #expect(closet.distance(of: race, workouts: runs) == 21_000)
        closet.assign(runs[0].id, to: nil)
        #expect(closet.distance(of: daily, workouts: runs) == 0)
    }

    @Test func retiredDefaultStopsCounting() throws {
        var closet = ShoeCloset()
        var old = Shoe(name: "Viejas", startDate: base)
        closet.upsert(old)
        old.isRetired = true
        closet.upsert(old)
        #expect(closet.shoe(for: workout(1, km: 5)) == nil)
        closet.remove(old.id)
        #expect(closet.shoes.isEmpty && closet.defaultShoeID == nil)
        let defaults = try #require(UserDefaults(suiteName: "shoes-\(UUID().uuidString)"))
        closet.upsert(Shoe(name: "Nuevas", startDate: base))
        ShoeStorage.save(closet, to: defaults)
        #expect(ShoeStorage.load(from: defaults) == closet)
    }
}
