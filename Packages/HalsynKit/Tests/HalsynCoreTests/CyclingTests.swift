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
private let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!

/// Una lectura por segundo con la potencia que devuelve `watts`.
private func samples(seconds: Int, from origin: Date = start, watts: (Int) -> Double) -> [PowerSample] {
    (0..<seconds).map { second in
        let date = origin.addingTimeInterval(Double(second))
        return PowerSample(start: date, end: date.addingTimeInterval(1), watts: watts(second))
    }
}

private func ride(_ date: Date, km: Double, kmh: Double, activity: WorkoutActivity = .outdoorRide, climb: Double? = nil, power: Double? = nil) -> WorkoutSummary {
    WorkoutSummary(activity: activity, start: date, duration: km / kmh * 3600, distanceMeters: km * 1000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo, averagePower: power, elevationGain: climb)
}

@Suite("CYKEL · potencia")
struct CyclingPowerTests {
    @Test func steadyHourAtFTPIsHundredTSS() throws {
        let summary = try #require(PowerAnalysis.summary(samples(seconds: 3600) { _ in 250 }))
        #expect(summary.duration == 3600)
        #expect(abs(summary.averagePower - 250) < 0.001)
        #expect(abs((summary.normalizedPower ?? 0) - 250) < 0.001)
        #expect(abs((summary.intensityFactor(ftp: 250) ?? 0) - 1) < 0.001)
        #expect(abs((summary.trainingStressScore(ftp: 250) ?? 0) - 100) < 0.01)
        // Una hora a 200 W con FTP 250: IF 0,8 → TSS 64.
        let easy = try #require(PowerAnalysis.summary(samples(seconds: 3600) { _ in 200 }))
        #expect(abs((easy.trainingStressScore(ftp: 250) ?? 0) - 64) < 0.01)
    }

    @Test func variableEffortRaisesNormalizedPower() throws {
        // Bloques de 2 min a 300 W y 100 W: media 200, NP mayor.
        let summary = try #require(PowerAnalysis.summary(samples(seconds: 3600) { ($0 / 120) % 2 == 0 ? 300 : 100 }))
        #expect(abs(summary.averagePower - 200) < 0.5)
        let normalized = try #require(summary.normalizedPower)
        #expect(normalized > 230 && normalized < 260)
        #expect(summary.maxPower == 300)
    }

    @Test func gapsSplitTheSeriesAndAreNotCounted() {
        let first = samples(seconds: 600) { _ in 200 }
        // 10 minutos de pausa sin lecturas, luego otros 10 minutos.
        let second = samples(seconds: 600, from: start.addingTimeInterval(1200)) { _ in 200 }
        let segments = PowerAnalysis.secondsSeries(first + second)
        #expect(segments.count == 2)
        #expect(segments.map(\.count) == [600, 600])
        // 20 minutos de datos pero no seguidos: no hay mejor media de 20 min.
        #expect(PowerAnalysis.bestAverage(segments: segments, seconds: 1200) == nil)
        #expect(PowerAnalysis.bestAverage(segments: segments, seconds: 300) == 200)
    }

    @Test func sparseReadingsHoldUntilTheNextOne() {
        // Una lectura cada 2 s (sensor que informa más despacio).
        let sparse = stride(from: 0, to: 60, by: 2).map { second -> PowerSample in
            let date = start.addingTimeInterval(Double(second))
            return PowerSample(start: date, end: date, watts: second < 30 ? 100 : 300)
        }
        let segments = PowerAnalysis.secondsSeries(sparse)
        #expect(segments.count == 1)
        #expect(segments[0].count == 59)
        #expect(segments[0].prefix(30).allSatisfy { $0 == 100 })
    }

    @Test func longBackToBackReadingsAreOneSeries() throws {
        // Lecturas de 10 s y de 60 s seguidas (otras apps o series agrupadas).
        for length in [10, 60] {
            let readings = (0..<(1800 / length)).map { index -> PowerSample in
                let date = start.addingTimeInterval(Double(index * length))
                return PowerSample(start: date, end: date.addingTimeInterval(Double(length)), watts: 200)
            }
            let segments = PowerAnalysis.secondsSeries(readings)
            #expect(segments.count == 1)
            #expect(segments.first?.count == 1800)
            let summary = try #require(PowerAnalysis.summary(segments: segments))
            #expect(summary.best20Minutes == 200)
            #expect(abs((summary.normalizedPower ?? 0) - 200) < 0.001)
        }
    }

    @Test func shortRidesHaveNoNormalizedPower() throws {
        let summary = try #require(PowerAnalysis.summary(samples(seconds: 200) { _ in 250 }))
        #expect(summary.normalizedPower == nil)
        #expect(summary.trainingStressScore(ftp: 250) == nil)
    }

    @Test func implausibleReadingsAreDropped() {
        let series = PowerAnalysis.secondsSeries([
            PowerSample(start: start, end: start.addingTimeInterval(1), watts: 4000),
            PowerSample(start: start.addingTimeInterval(1), end: start.addingTimeInterval(2), watts: -5),
        ])
        #expect(series.isEmpty)
    }

    @Test func cogganZones() {
        #expect(PowerZones.zones.count == 7)
        #expect(PowerZones.zone(for: 100, ftp: 250) == 1)   // 40 %
        #expect(PowerZones.zone(for: 137.5, ftp: 250) == 1) // 55 % exacto: techo de Z1
        #expect(PowerZones.zone(for: 180, ftp: 250) == 2)   // 72 %
        #expect(PowerZones.zone(for: 250, ftp: 250) == 4)   // 100 %
        #expect(PowerZones.zone(for: 290, ftp: 250) == 5)   // 116 %
        #expect(PowerZones.zone(for: 360, ftp: 250) == 6)   // 144 %
        #expect(PowerZones.zone(for: 600, ftp: 250) == 7)
        #expect(PowerZones.zone(for: 200, ftp: 0) == nil)
        let threshold = PowerZones.zones[3].watts(ftp: 250)
        #expect(abs(threshold.lower - 225) < 0.001 && abs((threshold.upper ?? 0) - 262.5) < 0.001)
        #expect(PowerZones.zones[6].upperFraction == nil)
        let seconds = PowerAnalysis.zoneSeconds(segments: [[100, 100, 250, 600]], ftp: 250)
        #expect(seconds[1] == 2 && seconds[4] == 1 && seconds[7] == 1)
    }

    @Test func ftpFromBestTwentyMinutes() throws {
        let hard = ride(calendar.date(byAdding: .day, value: -10, to: today)!, km: 40, kmh: 30)
        let old = ride(calendar.date(byAdding: .day, value: -60, to: today)!, km: 40, kmh: 32)
        let easy = ride(calendar.date(byAdding: .day, value: -3, to: today)!, km: 30, kmh: 25)
        let estimate = try #require(FTPEstimator.estimate(rides: [(hard, 280), (old, 320), (easy, nil)], today: today, calendar: calendar))
        // 95 % de 280 W; la de hace 60 días queda fuera de la ventana de 42.
        #expect(estimate.watts == 266)
        #expect(estimate.rideID == hard.id)
        #expect(FTPEstimator.estimate(rides: [(easy, nil)], today: today, calendar: calendar) == nil)
    }
}

@Suite("CYKEL · velocidad y estadísticas")
struct CyclingStatsTests {
    @Test func wallClockEndIncludesPauses() {
        let paused = WorkoutSummary(activity: .outdoorRide, start: start, duration: 3600, distanceMeters: 30_000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo, endDate: start.addingTimeInterval(4200))
        #expect(paused.end == start.addingTimeInterval(3600))
        #expect(paused.wallClockEnd == start.addingTimeInterval(4200))
        let unknown = ride(start, km: 30, kmh: 30)
        #expect(unknown.wallClockEnd == unknown.end)
    }

    @Test func speedFormatting() throws {
        let speed = try #require(Speed(distanceMeters: 30_000, duration: 3600))
        #expect(abs(speed.value(in: .metric) - 30) < 0.0001)
        #expect(abs(speed.value(in: .imperial) - 18.641) < 0.001)
        #expect(speed.formatted(in: .metric, locale: Locale(identifier: "es_ES")) == "30,0")
        #expect(UnitSystem.imperial.speedUnitSymbol == "mph")
        #expect(Speed(distanceMeters: 5, duration: 10) == nil)
        let fromPace = try #require(Speed(pace: Pace(secondsPerKilometer: 120)))
        #expect(abs(fromPace.value(in: .metric) - 30) < 0.0001)
    }

    @Test func rideStatsOnlyCountRides() throws {
        let workouts = [
            ride(calendar.date(byAdding: .day, value: -1, to: today)!, km: 60, kmh: 30, climb: 700, power: 190),
            ride(calendar.date(byAdding: .day, value: -2, to: today)!, km: 30, kmh: 25, activity: .indoorRide, power: 210),
            WorkoutSummary(activity: .outdoorRun, start: calendar.date(byAdding: .day, value: -1, to: today)!, duration: 3000, distanceMeters: 10_000, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo),
        ]
        let stats = RunningStatsBuilder.build(runs: workouts, period: .week, today: today, calendar: calendar, sport: .cycling)
        #expect(stats.current.count == 2)
        #expect(stats.current.distance == 90_000)
        // 90 km en 3 h 12 min → 28,125 km/h.
        #expect(abs((stats.current.averageSpeed?.value(in: .metric) ?? 0) - 28.125) < 0.001)
        #expect(stats.current.elevationGain == 700)
        // Potencia media ponderada por duración: (190·2 h + 210·1,2 h) / 3,2 h.
        #expect(abs((stats.current.averagePower ?? 0) - 197.5) < 0.01)
        #expect(stats.records.mostClimbing?.elevationGain == 700)
        // 20 km o más para "más rápida": las dos cuentan; la de 30 km/h gana.
        #expect(stats.records.fastest?.distanceMeters == 60_000)
        let running = RunningStatsBuilder.build(runs: workouts, period: .week, today: today, calendar: calendar)
        #expect(running.current.count == 1)
    }

    @Test func rideSettings() {
        var settings = RunSettings()
        settings.alerts.paceEnabled = true
        settings.alerts.zoneEnabled = true
        #expect(settings.rideAutoLapDistance == 5000)
        let ride = settings.forRide()
        #expect(ride.autoLapDistance == 5000)
        #expect(!ride.alerts.paceEnabled && !ride.alerts.zoneEnabled)
        settings.rideLapUnits = 0
        #expect(settings.rideAutoLapUnits == 0 && settings.rideAutoLapDistance == nil)
        settings.rideAutoLapUnits = nil
        settings.unitSystem = .imperial
        #expect(abs((settings.rideAutoLapDistance ?? 0) - 8046.72) < 0.01)
        // Una elección explícita se conserva en unidades al cambiar de km a mi.
        settings.unitSystem = .metric
        settings.rideLapUnits = 10
        settings.unitSystem = .imperial
        #expect(abs((settings.rideAutoLapDistance ?? 0) - 16_093.44) < 0.01)
        settings.functionalThresholdPower = 2000
        #expect(settings.validFunctionalThresholdPower == nil)
        settings.functionalThresholdPower = 245
        #expect(settings.validFunctionalThresholdPower == 245)
    }

    @Test func oldSettingsDecodeWithRideDefaults() throws {
        // Ajustes guardados antes de CYKEL (sin las claves nuevas).
        let data = try RunSettings().encoded()
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "rideAutoLapUnits")
        json.removeValue(forKey: "functionalThresholdPower")
        let decoded = try RunSettings.decoded(from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.rideAutoLapDistance == 5000)
        #expect(decoded.functionalThresholdPower == nil)
    }

    @Test func trackerSmoothsCyclingPowerAndDropsStaleReadings() {
        var settings = RunSettings()
        settings.functionalThresholdPower = 250
        var tracker = RunSessionTracker(settings: settings.forRide(), gpsConfiguration: .cycling)
        tracker.handle(.start, at: start)
        tracker.handle(.began, at: start)
        tracker.updateCyclingPower(200, average: 200, at: start.addingTimeInterval(1))
        tracker.updateCyclingPower(300, average: 250, at: start.addingTimeInterval(2))
        tracker.updateCadence(88, average: 86, at: start.addingTimeInterval(2))
        var snapshot = tracker.snapshot(at: start.addingTimeInterval(2))
        #expect(snapshot.power == 250)
        #expect(snapshot.averagePower == 250)
        #expect(snapshot.powerZone == 4)
        #expect(snapshot.cadence == 88 && snapshot.averageCadence == 86)
        // 0 W (rueda libre) es una lectura válida.
        tracker.updateCyclingPower(0, average: 240, at: start.addingTimeInterval(6))
        snapshot = tracker.snapshot(at: start.addingTimeInterval(6))
        #expect(snapshot.power == 0)
        // Sin lecturas en más de 6 s: vacío, no el último valor.
        snapshot = tracker.snapshot(at: start.addingTimeInterval(20))
        #expect(snapshot.power == nil && snapshot.cadence == nil)
        #expect(snapshot.averagePower == 240)
    }

    @Test func cyclingGPSAcceptsDownhillSpeeds() {
        // 18 m/s (65 km/h): imposible corriendo, normal bajando en bici.
        let points = (0..<20).map { second in
            LocationSample(latitude: 59.3 + Double(second) * 18 / 111_195, longitude: 18.1, altitude: 100 - Double(second), horizontalAccuracy: 5, verticalAccuracy: 3, timestamp: start.addingTimeInterval(Double(second)))
        }
        var running = GPSDistanceAccumulator()
        var cycling = GPSDistanceAccumulator(configuration: .cycling)
        points.forEach { running.add($0); cycling.add($0) }
        #expect(running.distance < 50)
        #expect(abs(cycling.distance - 342) < 2)
        let splits = RideAnalysis.splits(from: points)
        #expect(splits.count == 1 && splits[0].isComplete == false)
        let profile = RideAnalysis.profile(from: points, maxPoints: 5)
        #expect(profile.count == 5)
        #expect(abs((profile.last?.speed?.metersPerSecond ?? 0) - 18) < 0.5)
        #expect(RideAnalysis.elevationGain(points) == 0)
    }

    @Test func demoRidesAreLabelledAndHavePowerWhenStated() async throws {
        let provider = DemoHealthDataProvider(calendar: calendar, now: { today })
        let rides = await provider.recentRides(limit: 20)
        #expect(!rides.isEmpty)
        #expect(rides.allSatisfy { $0.activity.isRide && $0.origin.isDemo })
        let runs = await provider.recentWorkouts(limit: 40)
        #expect(Set(rides.map(\.id)).isDisjoint(with: runs.map(\.id)))
        let withPower = try #require(rides.first { $0.averagePower != nil })
        let power = await provider.ridePower(for: withPower)
        let summary = try #require(PowerAnalysis.summary(power))
        #expect(abs(summary.averagePower - (withPower.averagePower ?? 0)) < 2)
        if let indoor = rides.first(where: { $0.activity == .indoorRide }) {
            let detail = await provider.workoutDetail(for: indoor)
            #expect(detail.route.isEmpty && !detail.heartRate.isEmpty && !detail.power.isEmpty)
        }
    }
}

@Suite("CYKEL · zonas cardíacas de bici")
struct CyclingZonesTests {
    @Test func rideZonesDefaultToSpringAndCanBeOwn() throws {
        var settings = RunSettings()
        settings.zones = HeartRateZoneConfiguration(maxSource: .manual, maxHeartRate: 190)
        #expect(!settings.usesOwnRideZones)
        #expect(settings.forRide().zones == settings.zones)
        #expect(settings.zones(for: .cycling) == settings.zones)
        // Al activarlas se copian las de SPRING y después se editan aparte.
        settings.usesOwnRideZones = true
        settings.cyclingZones.maxHeartRate = 180
        #expect(settings.zones.maxHeartRate == 190)
        #expect(settings.forRide().zones.maxHeartRate == 180)
        #expect(settings.zones(for: .running).maxHeartRate == 190)
        #expect(settings.forRide().zones.zones.last?.upperBound == 180)
        // Al desactivarlas se vuelve a las de SPRING.
        settings.usesOwnRideZones = false
        #expect(settings.rideZones == nil && settings.forRide().zones.maxHeartRate == 190)
        // Viajan al reloj y se leen igual.
        settings.usesOwnRideZones = true
        let decoded = try RunSettings.decoded(from: settings.encoded())
        #expect(decoded.rideZones == settings.rideZones)
    }
}
