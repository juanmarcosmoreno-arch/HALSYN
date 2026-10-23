import Foundation
import Testing
@testable import HalsynCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// Metros por grado de latitud (aprox. constante cerca del ecuador usado en tests).
private let metersPerDegree = 111_195.0

/// Traza sintética: corre hacia el norte a `speed` m/s durante `seconds`, un punto
/// por segundo, con ruido gaussiano aproximado de `noise` metros (determinista).
private func trace(
    speed: Double,
    seconds: Int,
    noise: Double = 0,
    accuracy: Double = 5,
    start: Date = t0,
    startMeters: Double = 0,
    seed: UInt64 = 1
) -> [LocationSample] {
    var rng = SeededRandomNumberGenerator(seed: seed)
    return (0...seconds).map { second in
        let jitter = noise > 0 ? Double.random(in: -noise...noise, using: &rng) : 0
        let meters = startMeters + speed * Double(second) + jitter
        return LocationSample(
            latitude: meters / metersPerDegree,
            longitude: 0,
            altitude: nil,
            horizontalAccuracy: accuracy,
            timestamp: start.addingTimeInterval(Double(second))
        )
    }
}

@Suite("GPS · distancia")
struct GPSDistanceTests {
    @Test func haversineMatchesKnownDistance() {
        let a = LocationSample(latitude: 0, longitude: 0, horizontalAccuracy: 5, timestamp: t0)
        let b = LocationSample(latitude: 1000 / metersPerDegree, longitude: 0, horizontalAccuracy: 5, timestamp: t0)
        #expect(abs(a.distance(to: b) - 1000) < 0.5)
    }

    @Test func cleanTraceDistanceIsExact() {
        var gps = GPSDistanceAccumulator()
        trace(speed: 3.5, seconds: 600).forEach { gps.add($0) }
        #expect(abs(gps.distance - 2100) < 5)
    }

    @Test func noisyTraceStaysClose() {
        var gps = GPSDistanceAccumulator()
        trace(speed: 3.5, seconds: 600, noise: 3).forEach { gps.add($0) }
        // ±1,5 % con 3 m de ruido por punto.
        #expect(abs(gps.distance - 2100) / 2100 < 0.015)
    }

    @Test func standingStillDoesNotAddDistance() {
        var gps = GPSDistanceAccumulator()
        trace(speed: 0, seconds: 300, noise: 4, accuracy: 8).forEach { gps.add($0) }
        #expect(gps.distance < 15, "el GPS 'bailando' no debe sumar metros: \(gps.distance)")
    }

    @Test func curvesAreNotCutShort() {
        // Circunferencia de 400 m (radio ≈ 63,66 m) a 3,5 m/s, precisión 10 m, ruido ±2 m.
        let radius = 400 / (2 * Double.pi)
        var rng = SeededRandomNumberGenerator(seed: 9)
        var gps = GPSDistanceAccumulator()
        for second in 0...457 {   // ≈ 4 vueltas (1.600 m)
            let angle = 3.5 * Double(second) / radius
            let jitter = Double.random(in: -2...2, using: &rng)
            let x = (radius + jitter) * cos(angle), y = (radius + jitter) * sin(angle)
            gps.add(LocationSample(latitude: y / metersPerDegree, longitude: x / metersPerDegree, horizontalAccuracy: 10, timestamp: t0.addingTimeInterval(Double(second))))
        }
        let expected = 3.5 * 457
        #expect(abs(gps.distance - expected) / expected < 0.02, "\(gps.distance) frente a \(expected)")
    }

    @Test func inaccurateAndImpossiblePointsAreRejected() {
        var gps = GPSDistanceAccumulator()
        var points = trace(speed: 3, seconds: 60)
        // Punto con mala precisión y un salto de 500 m en 1 s.
        points.insert(LocationSample(latitude: 90 / metersPerDegree, longitude: 0, horizontalAccuracy: 80, timestamp: t0.addingTimeInterval(30.5)), at: 31)
        points.insert(LocationSample(latitude: 600 / metersPerDegree, longitude: 0, horizontalAccuracy: 5, timestamp: t0.addingTimeInterval(40.5)), at: 42)
        let accepted = points.map { gps.add($0) }
        #expect(accepted.filter { !$0 }.count == 2)
        #expect(abs(gps.distance - 180) < 5)
    }

    @Test func signalLossDoesNotInventDistance() {
        var gps = GPSDistanceAccumulator()
        trace(speed: 3, seconds: 60).forEach { gps.add($0) }
        // 2 minutos sin señal y reaparece 360 m más allá.
        trace(speed: 3, seconds: 60, start: t0.addingTimeInterval(180), startMeters: 540).forEach { gps.add($0) }
        #expect(abs(gps.distance - 360) < 5)
    }

    @Test func elevationGainUsesHysteresis() {
        var gps = GPSDistanceAccumulator()
        let altitudes: [Double] = [100, 101, 100, 102, 104, 103, 107, 110, 109, 111]
        for (i, altitude) in altitudes.enumerated() {
            gps.add(LocationSample(latitude: Double(i) * 3 / metersPerDegree, longitude: 0, altitude: altitude, horizontalAccuracy: 5, verticalAccuracy: 4, timestamp: t0.addingTimeInterval(Double(i))))
        }
        #expect(gps.elevationGain == 10, "100→104→107→110: solo subidas ≥ 3 m")
    }
}

@Suite("Ritmo")
struct PaceEstimatorTests {
    @Test func steadyPaceIsAccurate() throws {
        var estimator = PaceEstimator()
        for s in 0...60 { estimator.add(cumulativeDistance: Double(s) * 1000 / 300, at: t0.addingTimeInterval(Double(s))) }
        let pace = try #require(estimator.currentPace(at: t0.addingTimeInterval(60)))
        #expect(abs(pace.secondsPerKilometer - 300) < 1)
    }

    @Test func respondsToARealChangeWithinTheWindow() throws {
        var estimator = PaceEstimator()
        var distance = 0.0
        for s in 1...60 {
            distance += s <= 30 ? 1000.0 / 360 : 1000.0 / 240   // de 6:00 a 4:00 /km
            estimator.add(cumulativeDistance: distance, at: t0.addingTimeInterval(Double(s)))
        }
        let pace = try #require(estimator.currentPace(at: t0.addingTimeInterval(60)))
        #expect(abs(pace.secondsPerKilometer - 240) < 5)
    }

    @Test func smoothsGPSNoise() throws {
        var gps = GPSDistanceAccumulator()
        var estimator = PaceEstimator()
        for sample in trace(speed: 1000.0 / 300, seconds: 120, noise: 3) {
            gps.add(sample)
            estimator.add(cumulativeDistance: gps.distance, at: sample.timestamp)
        }
        let pace = try #require(estimator.currentPace(at: t0.addingTimeInterval(120)))
        // 5:00/km ± 25 s con ruido de 3 m por punto.
        #expect(abs(pace.secondsPerKilometer - 300) < 25)
    }

    @Test func stoppingClearsCurrentPace() {
        var estimator = PaceEstimator()
        for s in 0...30 { estimator.add(cumulativeDistance: Double(s) * 3, at: t0.addingTimeInterval(Double(s))) }
        for s in 31...60 { estimator.add(cumulativeDistance: 90, at: t0.addingTimeInterval(Double(s))) }
        #expect(estimator.currentPace(at: t0.addingTimeInterval(60)) == nil)
    }

    @Test func needsAMinimumSpan() {
        var estimator = PaceEstimator()
        estimator.add(cumulativeDistance: 0, at: t0)
        estimator.add(cumulativeDistance: 10, at: t0.addingTimeInterval(2))
        #expect(estimator.currentPace(at: t0.addingTimeInterval(2)) == nil)
    }
}

@Suite("Sesión, tiempo y vueltas")
struct RunSessionTests {
    @Test func stateMachineRejectsInvalidTransitions() {
        var machine = WorkoutStateMachine()
        let results = [
            machine.handle(.pause), machine.handle(.start), machine.handle(.began), machine.handle(.pause),
            machine.handle(.pause), machine.handle(.resume), machine.handle(.end), machine.handle(.resume),
            machine.handle(.finished),
        ]
        #expect(results == [false, true, true, true, false, true, true, false, true])
        #expect(machine.phase == .ended)
    }

    @Test func activeTimeExcludesPauses() {
        var timer = ActiveTimer()
        timer.begin(at: t0)
        timer.pause(at: t0.addingTimeInterval(100))
        #expect(timer.elapsed(at: t0.addingTimeInterval(160)) == 100)
        timer.resume(at: t0.addingTimeInterval(160))
        #expect(timer.elapsed(at: t0.addingTimeInterval(200)) == 140)
    }

    @Test func autoLapsAreInterpolated() {
        var laps = LapTracker(autoLapDistance: 1000)
        // 4 m/s: 1000 m a los 250 s. Actualizaciones cada 7 s para forzar interpolación.
        var completed: [Lap] = []
        for s in stride(from: 0, through: 540, by: 7) {
            completed += laps.update(distance: Double(s) * 4, elapsed: Double(s))
        }
        #expect(completed.count == 2)
        #expect(abs(completed[0].duration - 250) < 0.01)
        #expect(abs(completed[1].duration - 250) < 0.01)
        #expect(completed.allSatisfy { $0.trigger == .automatic && $0.distance == 1000 })
    }

    @Test func manualLapResetsTheCurrentLap() {
        var laps = LapTracker(autoLapDistance: nil)
        laps.update(distance: 400, elapsed: 100)
        let lap = laps.markLap(distance: 420, elapsed: 105)
        #expect(lap.distance == 420 && lap.duration == 105 && lap.trigger == .manual)
        laps.update(distance: 500, elapsed: 125)
        let current = laps.currentLap(distance: 500, elapsed: 125)
        #expect(current.distance == 80 && current.duration == 20)
    }

    @Test func fullRunWithPauseUsingGPS() throws {
        var tracker = RunSessionTracker(autoLapDistance: 1000)
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        // 5 min a 3,33 m/s (5:00/km) → 1000 m.
        for sample in trace(speed: 1000.0 / 300, seconds: 300) { tracker.addLocation(sample) }
        tracker.handle(.pause, at: t0.addingTimeInterval(300))
        // Durante la pausa los puntos no cuentan aunque se mueva (p. ej. caminando).
        for sample in trace(speed: 1.5, seconds: 60, start: t0.addingTimeInterval(301), startMeters: 1000) { tracker.addLocation(sample) }
        tracker.handle(.resume, at: t0.addingTimeInterval(360))
        for sample in trace(speed: 1000.0 / 300, seconds: 150, start: t0.addingTimeInterval(361), startMeters: 1100) { tracker.addLocation(sample) }

        let snapshot = tracker.snapshot(at: t0.addingTimeInterval(511))
        #expect(abs(snapshot.elapsed - 451) < 0.01, "excluye el minuto de pausa")
        #expect(abs(snapshot.distance - 1500) < 10)
        #expect(snapshot.laps.count == 1)
        let average = try #require(snapshot.averagePace)
        #expect(abs(average.secondsPerKilometer - 300) < 5)
        let firstConsume = tracker.consumeAutoLaps()
        let secondConsume = tracker.consumeAutoLaps()
        #expect(firstConsume.count == 1)
        #expect(secondConsume.isEmpty)
    }

    @Test func healthKitDistanceTakesPrecedence() {
        var tracker = RunSessionTracker()
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        for sample in trace(speed: 3, seconds: 100) { tracker.addLocation(sample) }
        tracker.updateDistance(total: 320, at: t0.addingTimeInterval(100))
        #expect(tracker.snapshot(at: t0.addingTimeInterval(100)).distance == 320)
        // La distancia de HealthKit nunca retrocede.
        tracker.updateDistance(total: 310, at: t0.addingTimeInterval(101))
        #expect(tracker.distance == 320)
    }

    @Test func heartRateStatsIgnoreImplausibleValues() {
        var tracker = RunSessionTracker()
        [140, 150, 0, 400, 160].forEach { tracker.addHeartRate($0) }
        let snapshot = tracker.snapshot(at: t0)
        #expect(snapshot.heartRate == 160)
        #expect(snapshot.averageHeartRate == 150)
        #expect(snapshot.maxHeartRate == 160)
    }

    @Test func fieldsWithoutLiveDataAreEmptyNotInvented() {
        let snapshot = RunSnapshot()
        for field in [WorkoutFieldKind.heartRateZone, .cadence, .runningPower, .targetPace, .intervalTime] {
            #expect(snapshot.value(for: field).value == nil)
        }
        #expect(snapshot.value(for: .heartRate).value == nil)
        #expect(snapshot.value(for: .elapsedTime).value == "0:00")
    }
}
