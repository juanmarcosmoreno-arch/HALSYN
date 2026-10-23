import Foundation
import Testing
@testable import HalsynCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite("SPRING Pro · zonas cardíacas")
struct HeartRateZoneTests {
    @Test func noZonesWithoutMaxHeartRate() {
        let config = HeartRateZoneConfiguration()
        #expect(config.zones.isEmpty)
        #expect(config.zone(for: 150) == nil)
    }

    @Test func implausibleMaxIsIgnored() {
        #expect(HeartRateZoneConfiguration(maxHeartRate: 300).zones.isEmpty)
        #expect(HeartRateZoneConfiguration(maxHeartRate: 80).zones.isEmpty)
    }

    @Test func percentOfMaxBoundaries() {
        let zones = HeartRateZoneConfiguration(maxHeartRate: 200).zones
        #expect(zones.map(\.lowerBound) == [100, 120, 140, 160, 180])
        #expect(zones.map(\.upperBound) == [120, 140, 160, 180, 200])
    }

    @Test func karvonenUsesReserve() {
        let config = HeartRateZoneConfiguration(method: .heartRateReserve, maxHeartRate: 190, restingHeartRate: 50)
        // 50 + 140 × 0,5 = 120; 50 + 140 × 0,9 = 176.
        #expect(config.zones.first?.lowerBound == 120)
        #expect(config.zones.last?.lowerBound == 176)
    }

    @Test func karvonenFallsBackWithoutResting() {
        let config = HeartRateZoneConfiguration(method: .heartRateReserve, maxHeartRate: 200)
        #expect(config.effectiveMethod == .percentOfMax)
        #expect(config.zones.first?.lowerBound == 100)
    }

    @Test func zoneLookup() {
        let config = HeartRateZoneConfiguration(maxHeartRate: 200)
        #expect(config.zone(for: 90) == 0)
        #expect(config.zone(for: 100) == 1)
        #expect(config.zone(for: 139) == 2)
        #expect(config.zone(for: 140) == 3)
        #expect(config.zone(for: 185) == 5)
        #expect(config.zone(for: 210) == 5)
    }

    @Test func observedMaxIgnoresSensorSpikes() {
        let workouts = [150.0, 182, 245].map {
            WorkoutSummary(activity: .outdoorRun, start: t0, duration: 1800, distanceMeters: 5000, averageHeartRate: 140, maxHeartRate: $0, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        }
        #expect(HeartRateZoneConfiguration.observedMax(in: workouts) == 182)
        #expect(HeartRateZoneConfiguration.observedMax(in: []) == nil)
    }

    @Test func zoneTimeCountsUntilNextReadingAndCapsGaps() {
        var time = ZoneTimeAccumulator()
        time.add(zone: 2, at: t0)
        time.add(zone: 3, at: t0.addingTimeInterval(5))
        // Hueco de 60 s sin lecturas: solo cuentan 15 s.
        time.add(zone: 3, at: t0.addingTimeInterval(65))
        time.breakSegment(at: t0.addingTimeInterval(70))
        #expect(time.seconds[2] == 5)
        #expect(time.seconds[3] == 20)
        #expect(time.total == 25)
    }

    @Test func pausedTimeIsNotCountedInZones() {
        var tracker = RunSessionTracker(settings: RunSettings(zones: HeartRateZoneConfiguration(maxHeartRate: 200)))
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.addHeartRate(150, at: t0)
        tracker.addHeartRate(150, at: t0.addingTimeInterval(10))
        tracker.handle(.pause, at: t0.addingTimeInterval(12))
        tracker.addHeartRate(150, at: t0.addingTimeInterval(100))
        tracker.handle(.resume, at: t0.addingTimeInterval(200))
        tracker.addHeartRate(170, at: t0.addingTimeInterval(201))
        tracker.addHeartRate(170, at: t0.addingTimeInterval(205))
        let snapshot = tracker.snapshot(at: t0.addingTimeInterval(205))
        #expect(snapshot.zoneSeconds[3] == 12)
        #expect(snapshot.zoneSeconds[4] == 4)
        #expect(snapshot.heartRateZone == 4)
        #expect(snapshot.value(for: .heartRateZone).value == "Z4")
    }

    @Test func zoneFieldIsEmptyWithoutConfiguration() {
        var tracker = RunSessionTracker()
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.addHeartRate(150, at: t0)
        #expect(tracker.snapshot(at: t0).value(for: .heartRateZone).value == nil)
    }
}

@Suite("SPRING Pro · intervalos")
struct IntervalTests {
    private let plan = IntervalPlan(id: "t", name: "Test", warmup: .time(60), work: .distance(400), workPace: PaceRange(fastest: 230, slowest: 240), recovery: .time(30), repeats: 3, cooldown: .open)

    @Test func expandsStepsWithoutTrailingRecovery() {
        let kinds = plan.steps.map(\.kind)
        #expect(kinds == [.warmup, .work, .recovery, .work, .recovery, .work, .cooldown])
        #expect(plan.steps.filter { $0.kind == .work }.map(\.repetition) == [1, 2, 3])
    }

    @Test func repeatsAreClamped() {
        #expect(IntervalPlan(id: "x", name: "x", warmup: nil, work: .time(10), recovery: .time(10), repeats: 0, cooldown: nil).repeats == 1)
        #expect(IntervalPlan(id: "x", name: "x", warmup: nil, work: .time(10), recovery: .time(10), repeats: 99, cooldown: nil).repeats == 30)
    }

    @Test func advancesByTimeAndDistance() {
        var tracker = IntervalTracker(plan: plan)
        #expect(tracker.update(distance: 150, elapsed: 59).isEmpty)
        let started = tracker.update(distance: 160, elapsed: 61)
        #expect(started.first?.step.kind == .work)
        // La serie cuenta desde el cruce exacto del calentamiento.
        #expect(tracker.progress()?.elapsed == 1)
        #expect(tracker.update(distance: 559, elapsed: 150).isEmpty)
        #expect(tracker.update(distance: 562, elapsed: 151).first?.step.kind == .recovery)
        #expect(tracker.progress()?.distance == 2)
    }

    @Test func lateUpdateCanCompleteSeveralSteps() {
        let quick = IntervalPlan(id: "q", name: "q", warmup: nil, work: .time(10), recovery: .time(10), repeats: 2, cooldown: nil)
        var tracker = IntervalTracker(plan: quick)
        let started = tracker.update(distance: 0, elapsed: 25)
        #expect(started.map(\.step.kind) == [.recovery, .work])
        #expect(tracker.progress()?.elapsed == 5)
    }

    @Test func openStepNeedsLapButton() {
        var tracker = IntervalTracker(plan: IntervalPlan(id: "o", name: "o", warmup: .open, work: .time(60), recovery: .time(60), repeats: 1, cooldown: nil))
        #expect(tracker.update(distance: 2000, elapsed: 900).isEmpty)
        #expect(tracker.progress()?.remaining == nil)
        #expect(tracker.advance(distance: 2000, elapsed: 900)?.step.kind == .work)
        tracker.update(distance: 2300, elapsed: 960)
        #expect(tracker.isFinished)
        #expect(tracker.progress() == nil)
    }

    @Test func sessionTracksIntervalsAndCues() {
        let quick = IntervalPlan(id: "q", name: "2 × 200 m", warmup: .open, work: .distance(200), workPace: PaceRange(fastest: 230, slowest: 250), recovery: .time(30), repeats: 2, cooldown: nil)
        var tracker = RunSessionTracker(settings: RunSettings(), plan: quick)
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.updateDistance(total: 500, at: t0.addingTimeInterval(180))
        #expect(tracker.snapshot(at: t0.addingTimeInterval(180)).interval?.step.kind == .warmup)
        // El botón de vuelta termina el calentamiento abierto.
        tracker.markLap(at: t0.addingTimeInterval(180))
        var snapshot = tracker.snapshot(at: t0.addingTimeInterval(180))
        #expect(snapshot.interval?.step.kind == .work)
        #expect(snapshot.paceTarget == PaceRange(fastest: 230, slowest: 250))
        #expect(snapshot.value(for: .intervalTime).value == "200")

        tracker.updateDistance(total: 700, at: t0.addingTimeInterval(228))
        snapshot = tracker.snapshot(at: t0.addingTimeInterval(228))
        #expect(snapshot.interval?.step.kind == .recovery)
        #expect(snapshot.paceTarget == nil, "en recuperación no hay objetivo de ritmo")
        // La recuperación por tiempo avanza aunque no cambie la distancia.
        tracker.tick(at: t0.addingTimeInterval(259))
        #expect(tracker.snapshot(at: t0.addingTimeInterval(259)).interval?.repetitionKind == .work)
        tracker.updateDistance(total: 900, at: t0.addingTimeInterval(300))

        let cues = tracker.consumeCues()
        let steps = cues.compactMap { cue -> IntervalStepKind? in
            if case let .intervalStep(progress) = cue { return progress.step.kind }
            return nil
        }
        #expect(steps == [.work, .recovery, .work])
        #expect(cues.contains(.intervalsCompleted))
        #expect(tracker.snapshot(at: t0.addingTimeInterval(300)).intervalsCompleted)
        #expect(tracker.consumeCues().isEmpty)
    }
}

private extension IntervalProgress {
    var repetitionKind: IntervalStepKind { step.kind }
}

@Suite("SPRING Pro · alertas")
struct RunAlertTests {
    private let range = PaceRange(fastest: 300, slowest: 330)

    private func run(_ engine: inout RunAlertEngine, pace seconds: Double?, at offset: TimeInterval, zone: Int? = nil) -> [RunAlert] {
        engine.evaluate(pace: seconds.map { Pace(secondsPerKilometer: $0) }, paceTarget: range, zone: zone, at: t0.addingTimeInterval(offset))
    }

    @Test func briefSpikeDoesNotAlert() {
        var engine = RunAlertEngine()
        #expect(run(&engine, pace: 280, at: 0).isEmpty)
        #expect(run(&engine, pace: 280, at: 5).isEmpty)
        #expect(run(&engine, pace: 310, at: 6).isEmpty)
        #expect(run(&engine, pace: 280, at: 12).isEmpty)
    }

    @Test func sustainedDeviationAlertsOnceThenRepeats() {
        var engine = RunAlertEngine()
        var alerts: [RunAlert] = []
        for second in stride(from: 0.0, through: 75, by: 1) {
            alerts += run(&engine, pace: 360, at: second)
        }
        // A los 10 s y otra vez a los 70 s (cada 60 s).
        #expect(alerts == [.paceTooSlow, .paceTooSlow])
    }

    @Test func returningToRangeIsAnnounced() {
        var engine = RunAlertEngine()
        for second in stride(from: 0.0, through: 10, by: 1) {
            _ = run(&engine, pace: 280, at: second)
        }
        // En el borde (300 s/km) aún no cuenta como de vuelta (histéresis).
        #expect(run(&engine, pace: 301, at: 11).isEmpty)
        #expect(run(&engine, pace: 315, at: 12) == [.paceBackInRange])
        #expect(run(&engine, pace: 315, at: 13).isEmpty)
    }

    @Test func missingPaceResetsTheWait() {
        var engine = RunAlertEngine()
        #expect(run(&engine, pace: 360, at: 0).isEmpty)
        #expect(run(&engine, pace: nil, at: 8).isEmpty)
        #expect(run(&engine, pace: 360, at: 9).isEmpty)
        #expect(run(&engine, pace: 360, at: 18).isEmpty)
        #expect(run(&engine, pace: 360, at: 19) == [.paceTooSlow])
    }

    @Test func zoneAlerts() {
        var engine = RunAlertEngine(configuration: RunAlertConfiguration(zoneEnabled: true, lowestZone: 2, highestZone: 3))
        var alerts: [RunAlert] = []
        for second in stride(from: 0.0, through: 10, by: 1) {
            alerts += engine.evaluate(pace: nil, paceTarget: nil, zone: 4, at: t0.addingTimeInterval(second))
        }
        alerts += engine.evaluate(pace: nil, paceTarget: nil, zone: 3, at: t0.addingTimeInterval(11))
        #expect(alerts == [.heartRateAboveZone, .heartRateBackInZone])
    }

    @Test func zoneRangeIsOrdered() {
        let config = RunAlertConfiguration(lowestZone: 4, highestZone: 2)
        #expect(config.zoneRange == 2...4)
    }

    @Test func freeRunPaceAlertThroughTracker() {
        var settings = RunSettings()
        settings.alerts.paceEnabled = true
        settings.alerts.paceRange = range
        var tracker = RunSessionTracker(settings: settings)
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        // 4:00 /km (250 m/min): demasiado rápido para 5:00–5:30.
        for second in 1...40 {
            let date = t0.addingTimeInterval(Double(second))
            tracker.updateDistance(total: Double(second) * 1000 / 240, at: date)
            tracker.tick(at: date)
        }
        #expect(tracker.consumeCues().contains(.alert(.paceTooFast)))
        #expect(tracker.snapshot(at: t0.addingTimeInterval(40)).value(for: .targetPace).value == "5:00–5:30")
    }

    @Test func pauseDoesNotTriggerAlerts() {
        var settings = RunSettings()
        settings.alerts.paceEnabled = true
        var tracker = RunSessionTracker(settings: settings)
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.handle(.pause, at: t0.addingTimeInterval(1))
        for second in 2...60 {
            tracker.tick(at: t0.addingTimeInterval(Double(second)))
        }
        #expect(tracker.consumeCues().isEmpty)
    }
}

@Suite("SPRING Pro · ajustes y pantallas")
struct RunSettingsTests {
    @Test func roundTripsThroughJSON() throws {
        var settings = RunSettings(autoLapDistance: nil, zones: HeartRateZoneConfiguration(method: .heartRateReserve, maxSource: .observed, maxHeartRate: 188, restingHeartRate: 52), modifiedAt: t0)
        settings.alerts.zoneEnabled = true
        settings.intervalPlans.append(IntervalPlan(id: "c", name: "Custom", warmup: nil, work: .open, workPace: PaceRange(fastest: 240, slowest: 250), recovery: .distance(200), repeats: 4, cooldown: .time(120)))
        let decoded = try RunSettings.decoded(from: settings.encoded())
        #expect(decoded == settings)
    }

    @Test func corruptDataFallsBackToDefaults() {
        let defaults = UserDefaults(suiteName: "halsyn.tests.\(UUID().uuidString)")!
        defaults.set(Data("no es json".utf8), forKey: RunSettings.storageKey)
        #expect(RunSettings.load(from: defaults) == RunSettings())
    }

    @Test func saveAndLoad() {
        let defaults = UserDefaults(suiteName: "halsyn.tests.\(UUID().uuidString)")!
        let settings = RunSettings(autoLapDistance: 400, modifiedAt: t0)
        settings.save(to: defaults)
        #expect(RunSettings.load(from: defaults) == settings)
    }

    @Test func normalizedFillsTrimsAndDeduplicates() {
        let messy = WorkoutScreenProfile(id: "m", name: "M", layout: .three, fields: [.distance, .distance, .heartRate, .cadence, .lapPace])
        let fixed = messy.normalized()
        #expect(fixed.fields == [.distance, .heartRate, .cadence])
        #expect(fixed.isValid)
        let short = WorkoutScreenProfile(id: "s", name: "S", layout: .four, fields: [.heartRate]).normalized()
        #expect(short.isValid)
        #expect(short.fields.first == .heartRate)
    }

    @Test func layoutChangeKeepsFields() {
        let profile = WorkoutScreenProfile.easyRun.withLayout(.two)
        #expect(profile.fields == [.elapsedTime, .currentPace])
        let back = profile.withLayout(.four)
        #expect(back.isValid)
        #expect(Array(back.fields.prefix(2)) == [.elapsedTime, .currentPace])
    }

    @Test func replacingSwapsInsteadOfDuplicating() {
        let profile = WorkoutScreenProfile.easyRun.replacing(fieldAt: 0, with: .heartRate)
        #expect(profile.fields == [.heartRate, .currentPace, .elapsedTime, .heartRateZone])
        #expect(profile.isValid)
    }

    @Test func validScreensNeverEmpty() {
        #expect(RunSettings(screens: []).validScreens == [.easyRun])
        let many = Array(repeating: WorkoutScreenProfile.race, count: 6)
        #expect(RunSettings(screens: many).validScreens.count == RunSettings.maximumScreens)
    }

    @Test func powerFieldOnlyWithMeasurement() {
        var tracker = RunSessionTracker()
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        #expect(tracker.snapshot(at: t0).value(for: .runningPower).value == nil)
        tracker.updatePower(251)
        #expect(tracker.snapshot(at: t0).value(for: .runningPower).value == "251")
        #expect(tracker.snapshot(at: t0).value(for: .cadence).value == nil)
    }
}

@Suite("SPRING Pro · análisis del entrenamiento")
struct WorkoutAnalysisTests {
    private func straightRoute(speed: Double, seconds: Int, pauseAt: Int? = nil, pause: TimeInterval = 0) -> [LocationSample] {
        (0...seconds).map { second in
            let shift = pauseAt.map { second >= $0 ? pause : 0 } ?? 0
            return LocationSample(latitude: speed * Double(second) / 111_195, longitude: 0, horizontalAccuracy: 5, timestamp: t0.addingTimeInterval(Double(second) + shift))
        }
    }

    @Test func splitsPerKilometer() {
        let splits = WorkoutAnalysis.splits(from: straightRoute(speed: 3.5, seconds: 900))
        // 3150 m: 3 parciales completos + 150 m.
        #expect(splits.count == 4)
        #expect(splits.prefix(3).allSatisfy { $0.isComplete && abs($0.duration - 285.7) < 2 })
        #expect(splits.last?.isComplete == false)
        #expect(abs((splits.last?.distance ?? 0) - 150) < 5)
    }

    @Test func pausesDoNotInflateSplits() {
        let splits = WorkoutAnalysis.splits(from: straightRoute(speed: 4, seconds: 600, pauseAt: 100, pause: 120))
        #expect(abs((splits.first?.duration ?? 0) - 250) < 2)
    }

    @Test func splitsInMiles() {
        let splits = WorkoutAnalysis.splits(from: straightRoute(speed: 4, seconds: 900), unit: .imperial)
        #expect(splits.filter(\.isComplete).count == 2)
    }

    @Test func noRouteNoSplits() {
        #expect(WorkoutAnalysis.splits(from: []).isEmpty)
    }

    @Test func zoneSecondsFromSamples() {
        let samples = (0..<60).map { HeartRatePoint(date: t0.addingTimeInterval(Double($0) * 5), bpm: $0 < 30 ? 130 : 165) }
        let seconds = WorkoutAnalysis.zoneSeconds(samples, zones: HeartRateZoneConfiguration(maxHeartRate: 200))
        #expect(seconds[2] == 150)
        #expect(seconds[4] == 150)
        #expect(WorkoutAnalysis.zoneSeconds(samples, zones: HeartRateZoneConfiguration()).isEmpty)
    }

    @Test func simplifiedKeepsEnds() {
        let route = straightRoute(speed: 1, seconds: 100)
        let simple = WorkoutAnalysis.simplified(route, minimumSpacing: 10)
        #expect(simple.first == route.first)
        #expect(simple.last == route.last)
        #expect(simple.count < 15)
    }

    @Test func demoDetailIsDeterministicAndLabelled() async {
        let provider = DemoHealthDataProvider(now: { t0 })
        guard let workout = await provider.recentWorkouts(limit: 1).first else {
            Issue.record("sin carreras demo")
            return
        }
        let a = await provider.workoutDetail(for: workout)
        let b = await provider.workoutDetail(for: workout)
        #expect(a == b)
        #expect(a.origin == .demo)
        #expect(!a.route.isEmpty && !a.heartRate.isEmpty)
        let total = WorkoutAnalysis.splits(from: a.route).map(\.distance).reduce(0, +)
        #expect(abs(total - (workout.distanceMeters ?? 0)) / (workout.distanceMeters ?? 1) < 0.08)
    }

    @Test func liveDetailIsEmptyWithoutData() async {
        let provider = DemoHealthDataProvider(now: { t0 })
        let treadmill = WorkoutSummary(activity: .indoorRun, start: t0, duration: 1200, distanceMeters: nil, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        #expect(await provider.workoutDetail(for: treadmill).route.isEmpty)
    }
}

@Suite("SPRING Pro · textos de intervalos")
struct IntervalFormatterTests {
    private let locale = Locale(identifier: "es_ES")

    @Test func goals() {
        #expect(IntervalPlanFormatter.goal(.time(45), locale: locale) == "45 s")
        #expect(IntervalPlanFormatter.goal(.time(600), locale: locale) == "10 min")
        #expect(IntervalPlanFormatter.goal(.time(90), locale: locale) == "1:30")
        #expect(IntervalPlanFormatter.goal(.distance(400), locale: locale) == "400 m")
        #expect(IntervalPlanFormatter.goal(.distance(1000), locale: locale) == "1,00 km")
    }

    @Test func summary() {
        let plan = IntervalPlan.presets[0]
        #expect(IntervalPlanFormatter.summary(plan, locale: locale) == "10 min · 6 × 400 m / 1:30 · 5 min")
        let single = IntervalPlan(id: "s", name: "s", warmup: nil, work: .time(1200), recovery: .time(60), repeats: 1, cooldown: nil)
        #expect(IntervalPlanFormatter.summary(single, locale: locale) == "1 × 20 min")
    }
}

@Suite("SPRING · gráfico en vivo")
struct LiveChartTests {
    @Test func samplesEveryFiveSecondsWhileRunning() {
        var tracker = RunSessionTracker()
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        for second in 1...60 {
            let date = t0.addingTimeInterval(Double(second))
            tracker.updateDistance(total: Double(second) * 3.5, at: date)
            tracker.addHeartRate(150, at: date)
            tracker.tick(at: date)
        }
        let snapshot = tracker.snapshot(at: t0.addingTimeInterval(60))
        // Desde que hay ritmo (≥ 2 lecturas) cada 5 s.
        #expect(snapshot.paceSamples.count >= 10 && snapshot.paceSamples.count <= 12)
        #expect(zip(snapshot.paceSamples, snapshot.paceSamples.dropFirst()).allSatisfy { $1.elapsed - $0.elapsed >= 5 })
        #expect(abs((snapshot.paceSamples.last?.value ?? 0) - 1000 / 3.5) < 5)
        #expect(snapshot.heartRateSamples.allSatisfy { $0.value == 150 })
    }

    @Test func noSamplesWhilePaused() {
        var tracker = RunSessionTracker()
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.handle(.pause, at: t0.addingTimeInterval(1))
        for second in 2...60 {
            tracker.addHeartRate(120, at: t0.addingTimeInterval(Double(second)))
            tracker.tick(at: t0.addingTimeInterval(Double(second)))
        }
        #expect(tracker.snapshot(at: t0.addingTimeInterval(60)).heartRateSamples.isEmpty)
    }

    @Test func smoothingAndDownsampling() {
        let samples = (0..<100).map { LiveSample(elapsed: Double($0) * 5, value: $0 % 2 == 0 ? 300 : 310) }
        let smooth = samples.smoothed(window: 3)
        #expect(smooth.count == 100)
        #expect(smooth.dropFirst().dropLast().allSatisfy { abs($0.value - 305) < 3.4 })
        let reduced = samples.downsampled(maxPoints: 20)
        #expect(reduced.count == 20)
        #expect(reduced.allSatisfy { abs($0.value - 305) <= 1 })
        #expect([LiveSample]().downsampled(maxPoints: 5).isEmpty)
    }
}
