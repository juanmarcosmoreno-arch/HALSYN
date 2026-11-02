import Foundation
import Testing
@testable import HalsynCore

@Suite("Calentamiento y calma fuera del entrenamiento grabado")
struct IntervalSessionLayoutTests {
    private let plan = IntervalPlan(id: "6x400", name: "6 × 400 m", warmup: .time(600), work: .distance(400), recovery: .time(90), repeats: 6, cooldown: .time(300))

    @Test func warmupAndCooldownLeaveTheRecordedPlan() {
        let layout = IntervalSessionLayout(plan: plan, measuresRecovery: true, defaultRecoveryMinutes: 2)
        #expect(layout.warmup == .time(600))
        #expect(layout.recorded.warmup == nil && layout.recorded.cooldown == nil)
        #expect(layout.recorded.steps.first?.kind == .work)
        #expect(layout.recorded.steps.last?.kind == .work)
        #expect(layout.recoveryMinutes == 5)
    }

    @Test func cooldownStaysWithoutRecovery() {
        let layout = IntervalSessionLayout(plan: plan, measuresRecovery: false, defaultRecoveryMinutes: 2)
        #expect(layout.recoveryMinutes == nil)
        #expect(layout.recorded.cooldown == .time(300))
        #expect(layout.recorded.warmup == nil)
    }

    @Test func recoveryMinutes() {
        #expect(IntervalSessionLayout.minutes(for: .distance(2000), default: 2) == 2)
        #expect(IntervalSessionLayout.minutes(for: .time(20), default: 2) == 1)
        #expect(IntervalSessionLayout.minutes(for: .time(1800), default: 2) == 10)
        #expect(IntervalSessionLayout.minutes(for: .open, default: 5) == 5)
    }
}

@Suite("Tipos de entrenamiento")
struct WorkoutStyleTests {
    @Test func templatesAndLabels() {
        let hills = WorkoutStyle.hills.template(id: "h", name: "R")
        #expect(hills.kind == .hills && hills.work == .time(45) && hills.repeats == 8)
        #expect(hills.kind.label(for: .work) == "SUBIDA" && hills.kind.title(for: .recovery) == "Bajada")
        #expect(WorkoutStyle.fartlek.label(for: .warmup) == "CALENTAR")
        let long = WorkoutStyle.long.template(id: "l", name: "F")
        #expect(long.steps.count == 1 && long.steps[0].kind == .work)
        #expect(IntervalPlanFormatter.summary(long, locale: Locale(identifier: "es_ES")) == "15 km")
    }

    @Test func oldPlansDecodeAsIntervals() throws {
        let old = #"{"id":"x","name":"x","work":{"distance":{"_0":400}},"recovery":{"time":{"_0":90}},"repeats":4}"#
        let plan = try JSONDecoder().decode(IntervalPlan.self, from: Data(old.utf8))
        #expect(plan.style == nil && plan.kind == .intervals)
        let encoded = try JSONEncoder().encode(WorkoutStyle.hills.template(id: "h", name: "R"))
        #expect(try JSONDecoder().decode(IntervalPlan.self, from: encoded).kind == .hills)
    }
}

@Suite("Color del anillo del reloj")
struct WorkoutRingColorTests {
    @Test func defaultsToGreenAndContrastsWithBlack() throws {
        #expect(RunSettings().ringColor == .green)
        let black = HalsynRGBColor(hex: 0x000000)
        for color in WorkoutRingColor.allCases {
            guard let rgb = color.rgb else { continue }
            // Muy por encima de 4,5:1 (WCAG AA) sobre el negro del reloj.
            #expect(rgb.contrastRatio(with: black) >= 7, "\(color)")
        }
        let old = try JSONEncoder().encode(RunSettings())
        #expect(try JSONDecoder().decode(RunSettings.self, from: old).ringColor == .green)
    }
}

@Suite("Carrera libre con objetivo")
struct GoalRunTests {
    @Test func goalRunPlans() throws {
        #expect(IntervalPlan.goalRun(distance: nil, pace: nil, name: "x") == nil)
        let distance = try #require(IntervalPlan.goalRun(distance: 5000, pace: nil, name: "x"))
        #expect(distance.isGoalRun && distance.steps.count == 1 && distance.steps[0].goal == .distance(5000) && distance.workPace == nil)
        let pace = try #require(IntervalPlan.goalRun(distance: 0, pace: Pace(secondsPerKilometer: 300), name: "x"))
        #expect(pace.steps[0].goal == .open && pace.steps[0].paceTarget == PaceRange(fastest: 295, slowest: 305))
    }

    @Test func paceStatus() {
        let range = PaceRange(center: Pace(secondsPerKilometer: 300), tolerance: 5)
        #expect(range.status(of: Pace(secondsPerKilometer: 310)) == .slower)
        #expect(range.status(of: Pace(secondsPerKilometer: 302)) == .onPace)
        #expect(range.status(of: Pace(secondsPerKilometer: 290)) == .faster)
    }
}

@Suite("Carrera libre con objetivo · vueltas")
struct GoalRunLapTests {
    @Test func lapDoesNotEndThePaceGoal() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = try #require(IntervalPlan.goalRun(distance: nil, pace: Pace(secondsPerKilometer: 300), name: "x"))
        var tracker = RunSessionTracker(settings: RunSettings(), plan: plan)
        tracker.handle(.start, at: t0)
        tracker.handle(.began, at: t0)
        tracker.updateDistance(total: 1000, at: t0.addingTimeInterval(300))
        tracker.markLap(at: t0.addingTimeInterval(300))
        let snapshot = tracker.snapshot(at: t0.addingTimeInterval(300))
        #expect(snapshot.interval?.step.kind == .work)
        #expect(snapshot.paceTarget == PaceRange(fastest: 295, slowest: 305))
    }
}

@Suite("Fuerza para corredores")
struct RunnerStrengthTests {
    @Test func everyGroupHasExercises() {
        for group in StrengthExercise.Group.allCases {
            #expect(!StrengthExercise.exercises(in: group).isEmpty, "\(group)")
        }
        #expect(Set(StrengthExercise.all.map(\.id)).count == StrengthExercise.all.count)
    }
}

@Suite("Widget · sesión de hoy")
struct WidgetSessionTests {
    @Test func sessionOnlyForItsDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = WidgetSnapshot(updatedAt: day, isDemo: false)
        snapshot.session = .init(date: day, title: "Rodaje suave", detail: "8 km", symbol: "figure.run", isRest: false)
        #expect(snapshot.session(on: day, calendar: calendar)?.title == "Rodaje suave")
        #expect(snapshot.session(on: day.addingTimeInterval(86_400 * 2), calendar: calendar) == nil)
        let data = try #require(WidgetSnapshotStore.encode(snapshot))
        let decoded = try #require(WidgetSnapshotStore.decode(data))
        #expect(decoded.session == snapshot.session)
        let old = try #require(WidgetSnapshotStore.encode(WidgetSnapshot(updatedAt: day, isDemo: true)))
        #expect(WidgetSnapshotStore.decode(old)?.session == nil)
    }
}

@Suite("Ruta para la tarjeta de compartir")
struct RouteProjectionTests {
    private func sample(_ latitude: Double, _ longitude: Double) -> LocationSample {
        LocationSample(latitude: latitude, longitude: longitude, altitude: nil, horizontalAccuracy: 5, verticalAccuracy: nil, timestamp: .now)
    }

    @Test func fitsInTheUnitSquareKeepingNorthUp() {
        // De sur a norte, en Buenos Aires.
        let points = RouteProjection.normalized([sample(-34.60, -58.40), sample(-34.59, -58.40), sample(-34.58, -58.39)])
        #expect(points.count == 3)
        #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(points[0].y > points[2].y, "el norte queda arriba")
        #expect(points[2].x > points[0].x, "el este queda a la derecha")
    }

    @Test func tooShortOrStillHasNoShape() {
        #expect(RouteProjection.normalized([sample(1, 1)]).isEmpty)
        #expect(RouteProjection.normalized([sample(1, 1), sample(1, 1)]).isEmpty)
    }

    @Test func reducesLongRoutes() {
        let route = (0..<5000).map { sample(-34.6 + Double($0) * 0.00001, -58.4) }
        let points = RouteProjection.normalized(route, maximumPoints: 400)
        #expect(points.count <= 402 && points.count > 300)
    }
}

@Suite("Clima de la carrera")
struct RunWeatherTests {
    @Test func heatBands() {
        #expect(HeatStress(temperature: 8, humidity: 0.9) == .cool)
        #expect(HeatStress(temperature: 17, humidity: 0.5) == .mild)
        #expect(HeatStress(temperature: 17, humidity: 0.85) == .warm)
        #expect(HeatStress(temperature: 22, humidity: 0.5) == .warm)
        #expect(HeatStress(temperature: 22, humidity: 0.8) == .hot)
        #expect(HeatStress(temperature: 28, humidity: nil) == .hot)
        #expect(HeatStress.warm > .mild)
    }

    @Test func humidityAsPercentOrFraction() {
        #expect(RunWeather(temperature: 20, humidity: 65, source: .health).humidity == 0.65)
        #expect(RunWeather(temperature: 20, humidity: 0.65, source: .weatherKit).humidity == 0.65)
    }
}
