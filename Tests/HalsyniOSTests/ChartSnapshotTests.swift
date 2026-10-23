import HalsynCore
import HalsynDesign
import SwiftUI
import XCTest
@testable import Halsyn

/// Renderiza las gráficas con datos demo en claro y oscuro para revisarlas a
/// ojo (CI las adjunta como artefacto "capturas-graficas"). Solo se ejecuta si
/// se define `SNAPSHOT_DIR`; no compara píxeles.
@MainActor
final class ChartSnapshotTests: XCTestCase {
    func testRenderCharts() async throws {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("SNAPSHOT_DIR no definido")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let provider = DemoHealthDataProvider()
        let today = Date.now
        let recovery = await provider.recoveryEstimates(endingOn: today, days: 28)
        let nights = await provider.sleepNights(endingOn: today, days: 14)
        let hrv = await provider.dailySeries(.heartRateVariability, days: 56, endingOn: today)
        let steps = await provider.dailySeries(.steps, days: 7, endingOn: today)
        let scores = await provider.dailyScores(endingOn: today, days: 30)
        let night = try XCTUnwrap(nights.last)

        let views: [(String, AnyView)] = [
            ("01-recuperacion", AnyView(RecoveryCard(estimate: recovery.last, history: recovery))),
            ("02-anoche", AnyView(LastNightCard(night: night, targetHours: 8))),
            ("03-noches", AnyView(SleepScheduleCard(nights: nights, targetHours: .constant(8)))),
            ("04-hrv", AnyView(BaselineTrendCard(title: "Variabilidad cardíaca (HRV)", eyebrow: "PULS", series: hrv, unit: "ms", explanation: "Ejemplo"))),
            ("05-pasos", AnyView(HalsynCard { HalsynTrendChart(values: steps.values, title: "Pasos", style: .bar, target: 8000, unit: "pasos").frame(height: 210) })),
            ("06-puntuacion", AnyView(HalsynCard { HalsynTrendChart(values: scores.map { DailyValue(day: $0.day, value: Double($0.value)) }, title: "Puntuación", yDomain: 0...100, usualRange: usualRange(scores.map { Double($0.value) })).frame(height: 230) })),
        ]
        for (name, view) in views {
            for scheme in [ColorScheme.light, .dark] {
                let content = view
                    .padding(16)
                    .frame(width: 390)
                    .background(Color.halsynBackground)
                    .environment(\.colorScheme, scheme)
                    .environment(AppModel(provider: provider))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage, "no se pudo renderizar \(name)")
                let data = try XCTUnwrap(image.pngData())
                try data.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "oscuro" : "claro").png"))
            }
        }
    }
}
