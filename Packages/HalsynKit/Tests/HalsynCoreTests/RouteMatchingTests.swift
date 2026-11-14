import Foundation
import Testing
@testable import HalsynCore

@Suite("Recorridos repetidos")
struct RouteMatchingTests {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)
    private let origin = (lat: 59.33, lon: 18.06)

    /// Ruta a 3 m/s siguiendo una función de posición (metros este, norte) por metro recorrido.
    private func route(length: Double, noise: Double = 0, seed: Int = 1, path: (Double) -> (x: Double, y: Double)) -> [LocationSample] {
        var samples: [LocationSample] = []
        var state = UInt64(seed)
        func jitter() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 33) / Double(1 << 31) - 0.5) * 2 * noise
        }
        var meters = 0.0, second = 0.0
        while meters <= length {
            let p = path(meters)
            let lat = origin.lat + (p.y + jitter()) / 110_540
            let lon = origin.lon + (p.x + jitter()) / (111_320 * cos(origin.lat * .pi / 180))
            samples.append(LocationSample(latitude: lat, longitude: lon, horizontalAccuracy: 5, timestamp: base.addingTimeInterval(second)))
            meters += 3
            second += 1
        }
        return samples
    }

    private func fingerprint(_ samples: [LocationSample], day: Int = 0) -> RouteFingerprint {
        RouteMatching.fingerprint(id: UUID(), date: base.addingTimeInterval(Double(day) * 86_400), route: samples)!
    }

    private let straight: (Double) -> (x: Double, y: Double) = { ($0, 0) }

    @Test func sameRouteWithGPSNoiseMatches() throws {
        let a = fingerprint(route(length: 3000, noise: 6, seed: 1, path: straight))
        let b = fingerprint(route(length: 3000, noise: 6, seed: 2, path: straight), day: 1)
        let quality = try #require(RouteMatching.match(a, b))
        #expect(quality.isMatch)
        #expect(quality.coverage > 0.95)
    }

    @Test func nearbyButDifferentStreetDoesNotMatch() {
        let a = fingerprint(route(length: 3000, path: straight))
        // Calle paralela a 120 m: misma distancia, otro recorrido.
        let b = fingerprint(route(length: 3000, path: { ($0, 120) }), day: 1)
        #expect(RouteMatching.match(a, b)?.isMatch != true)
    }

    @Test func reverseDirectionIsAnotherRoute() {
        let a = fingerprint(route(length: 3000, path: straight))
        let b = fingerprint(route(length: 3000, path: { (3000 - $0, 0) }), day: 1)
        #expect(RouteMatching.match(a, b)?.isMatch != true)
    }

    @Test func loopStartingElsewhereMatches() throws {
        let radius = 400.0
        let circumference = 2 * .pi * radius
        func circle(offset: Double) -> (Double) -> (x: Double, y: Double) {
            { m in
                let angle = (m + offset) / radius
                return (radius * cos(angle), radius * sin(angle))
            }
        }
        let a = fingerprint(route(length: circumference, noise: 4, seed: 3, path: circle(offset: 0)))
        let b = fingerprint(route(length: circumference, noise: 4, seed: 4, path: circle(offset: 600)), day: 1)
        #expect(a.isLoop && b.isLoop)
        let quality = try #require(RouteMatching.match(a, b))
        #expect(quality.isMatch)
        // El mismo circuito al revés no.
        let reverse = fingerprint(route(length: circumference, path: { m in circle(offset: 0)(circumference - m) }), day: 2)
        #expect(RouteMatching.match(a, reverse)?.isMatch != true)
    }

    @Test func outAndBackMatchesItself() throws {
        let outAndBack: (Double) -> (x: Double, y: Double) = { m in (m <= 1500 ? m : 3000 - m, 0) }
        let a = fingerprint(route(length: 3000, noise: 5, seed: 5, path: outAndBack))
        let b = fingerprint(route(length: 3000, noise: 5, seed: 6, path: outAndBack), day: 1)
        let quality = try #require(RouteMatching.match(a, b))
        #expect(quality.isMatch)
    }

    @Test func groupsDoNotChain() {
        let a = fingerprint(route(length: 3000, path: straight), day: 0)
        let b = fingerprint(route(length: 3100, path: straight), day: 1)
        let c = fingerprint(route(length: 3200, path: straight), day: 2)
        // Mismo trayecto con el GPS corrido 8 m hacia un costado.
        let d = fingerprint(route(length: 3000, path: { ($0, 8) }), day: 3)
        let groups = RouteMatching.groups([c, a, d, b])
        #expect(groups.count == 1)
        let group = groups[0]
        #expect(group.id == a.id)
        #expect(Set(group.members) == [a.id, b.id, d.id])
        #expect(!group.members.contains(c.id))
    }

    @Test func comparisonFlagsPausesAndRanks() throws {
        let ids = (0..<3).map { _ in UUID() }
        func run(_ index: Int, duration: TimeInterval, pause: TimeInterval = 0, hr: Double) -> WorkoutSummary {
            let start = base.addingTimeInterval(Double(index) * 86_400)
            return WorkoutSummary(id: ids[index], activity: .outdoorRun, start: start, duration: duration, distanceMeters: 5000, averageHeartRate: hr, maxHeartRate: hr + 15, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo, endDate: start.addingTimeInterval(duration + pause))
        }
        let runs = [run(0, duration: 1700, hr: 155), run(1, duration: 1650, hr: 152), run(2, duration: 1600, pause: 300, hr: 150)]
        let group = RouteGroup(id: ids[0], members: ids, distance: 5000, isLoop: false, quality: [:])
        let byID = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        let second = try #require(RouteComparisonEngine.compare(ids[1], group: group, runs: byID))
        #expect(second.rank == 1)
        #expect(second.versusPrevious == -50)
        #expect(second.heartRateVersusPrevious == -3)
        let paused = try #require(RouteComparisonEngine.compare(ids[2], group: group, runs: byID))
        #expect(paused.hasLongPauses)
        #expect(paused.rank == nil)
        #expect(paused.comparableCount == 2)
    }

    @Test func largeHistoryStaysFast() {
        var fingerprints: [RouteFingerprint] = []
        for index in 0..<120 {
            let offset = Double(index % 12) * 300
            fingerprints.append(fingerprint(route(length: 4000, noise: 4, seed: index, path: { ($0, offset) }), day: index))
        }
        let start = Date()
        let groups = RouteMatching.groups(fingerprints)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(groups.count == 12)
        #expect(groups.allSatisfy { $0.members.count == 10 })
    }
}

