import HalsynCore
import XCTest
@testable import Halsyn

/// Proveedor de prueba en modo `.live` que no toca HealthKit.
private struct StubLiveProvider: HealthDataProviding {
    let mode: DataMode = .live
    var authorizationFails = false

    func authorizationState() async -> HealthAuthorizationState { .requested }
    func requestAuthorization() async throws {
        if authorizationFails { throw HealthStoreError.failed("stub") }
    }
    func latest(_ kind: MetricKind, on day: Date) async -> MetricAvailability { .noData }
    func dailySeries(_ kind: MetricKind, days: Int, endingOn: Date) async -> MetricSeries {
        MetricSeries(kind: kind, values: [], origin: .healthKit(sourceName: nil))
    }
    func recentWorkouts(limit: Int) async -> [WorkoutSummary] { [] }
    func dailyScore(on day: Date) async -> DailyScore? { nil }
    func dailyScores(endingOn end: Date, days: Int) async -> [DailyScore] { [] }
    func recoveryScore(on day: Date) async -> DailyScore? { nil }
    func goals() async -> [Goal] { [] }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Tests de la capa de app (lógica de presentación) que dependen del target iOS.
/// La lógica de dominio se prueba en HalsynKit (`swift test`).
@MainActor
final class AppLayerTests: XCTestCase {
    /// XCTest crea una instancia por test: cada uno tiene sus propias preferencias.
    private let defaults = UserDefaults(suiteName: "HalsynTests-\(UUID().uuidString)")!

    private func makeModel(authorizationFails: Bool = false) -> AppModel {
        AppModel(defaults: defaults) { mode -> any HealthDataProviding in
            if mode == .live {
                return StubLiveProvider(authorizationFails: authorizationFails)
            }
            return DemoHealthDataProvider()
        }
    }

    func testAppStartsInDemoModeOnHalsaTab() {
        let model = makeModel()
        XCTAssertTrue(model.isDemo)
        XCTAssertEqual(model.dataMode, .demo)
        XCTAssertEqual(model.selectedTab, .halsa)
    }

    func testConnectingSwitchesToLiveAndPersists() async {
        let model = makeModel()
        let tokenBefore = model.reloadKey
        let connected = await model.connectAppleHealth()
        XCTAssertTrue(connected)
        XCTAssertEqual(model.dataMode, .live)
        XCTAssertNotEqual(model.reloadKey, tokenBefore)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.dataModeKey), "live")
        // Al reabrir la app se mantiene la fuente elegida.
        XCTAssertEqual(makeModel().dataMode, .live)
    }

    func testFailedConnectionKeepsDemo() async {
        let model = makeModel(authorizationFails: true)
        let connected = await model.connectAppleHealth()
        XCTAssertFalse(connected)
        XCTAssertTrue(model.isDemo)
    }

    func testBackToDemo() async {
        let model = makeModel()
        await model.connectAppleHealth()
        await model.useDemoData()
        XCTAssertTrue(model.isDemo)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.dataModeKey), "demo")
    }

    func testInsiktRelativeChange() {
        let series = MetricSeries(kind: .steps, values: [DailyValue(day: .now, value: 110)], origin: .demo)
        XCTAssertEqual(InsiktTrend(kind: .steps, current: series, previousAverage: 100).relativeChange ?? 0, 0.10, accuracy: 0.0001)
        XCTAssertNil(InsiktTrend(kind: .steps, current: series, previousAverage: nil).relativeChange)
        XCTAssertNil(InsiktTrend(kind: .steps, current: series, previousAverage: 0).relativeChange)
    }

    func testHalsaSnapshotLoadsLabelledDemoData() async {
        let snapshot = await HalsaSnapshot.load(from: DemoHealthDataProvider(seed: 1), unitSystem: .metric)
        XCTAssertEqual(snapshot.metrics.count, HalsaSnapshot.dashboardMetrics.count)
        XCTAssertEqual(snapshot.score?.origin, .demo)
        XCTAssertEqual(snapshot.stepsTrend.count, 7)
        XCTAssertTrue(snapshot.metrics.allSatisfy { $0.origin == .demo })
        XCTAssertNotNil(snapshot.score?.breakdown, "la puntuación demo sale de HealthScoreEngine")
        XCTAssertFalse(snapshot.summary.isEmpty)
    }

    func testScoreTextsCoverEveryFactorKind() {
        let factors: [ScoreFactor] = [
            ScoreFactor(kind: .sleepDuration(hours: 6.5), dimension: .sleep, impact: .neutral),
            ScoreFactor(kind: .restingHeartRate(deltaFromBaseline: 6), dimension: .cardiovascular, impact: .negative),
            ScoreFactor(kind: .heartRateVariability(relativeDeltaFromBaseline: -0.2), dimension: .cardiovascular, impact: .negative),
            ScoreFactor(kind: .averageSteps(perDay: 8500), dimension: .movement, impact: .positive),
            ScoreFactor(kind: .weeklyExercise(minutes: 180), dimension: .exercise, impact: .positive),
            ScoreFactor(kind: .trainingLoadRatio(1.6), dimension: .balance, impact: .negative),
        ]
        for factor in factors {
            _ = ScoreTexts.factor(factor)
        }
        XCTAssertEqual(ScoreTexts.hoursAndMinutes(7.25).contains("15"), true)
    }

    func testLiveSnapshotWithoutDataShowsNoValues() async {
        let snapshot = await HalsaSnapshot.load(from: StubLiveProvider(), unitSystem: .metric)
        XCTAssertNil(snapshot.score)
        XCTAssertTrue(snapshot.metrics.allSatisfy { $0.value == nil && $0.status != nil })
        XCTAssertTrue(snapshot.summary.isEmpty, "sin datos no se inventa un resumen")
    }

    func testEveryModuleHasAScreenEntryPoint() {
        // HÄLSA, SPRING, CYKEL e INSIKT son pestañas; VILA y MÅL se abren desde HÄLSA e INSIKT.
        XCTAssertEqual(Set(HalsynModule.allCases), [.halsa, .spring, .cykel, .insikt, .vila, .mal])
    }
}
