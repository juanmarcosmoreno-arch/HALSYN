import HalsynCore
import XCTest
@testable import Halsyn

/// Tests de la capa de app (lógica de presentación) que dependen del target iOS.
/// La lógica de dominio se prueba en HalsynKit (`swift test`).
@MainActor
final class AppLayerTests: XCTestCase {
    func testAppStartsInDemoModeOnHalsaTab() {
        let model = AppModel()
        XCTAssertTrue(model.isDemo)
        XCTAssertEqual(model.dataMode, .demo)
        XCTAssertEqual(model.selectedTab, .halsa)
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
    }

    func testEveryModuleHasAScreenEntryPoint() {
        // HÄLSA, SPRING e INSIKT son pestañas; VILA y MÅL se abren desde HÄLSA e INSIKT.
        XCTAssertEqual(Set(HalsynModule.allCases), [.halsa, .spring, .insikt, .vila, .mal])
    }
}
