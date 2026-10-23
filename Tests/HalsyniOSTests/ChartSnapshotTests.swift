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
        let report = await provider.computeInsights(endingOn: today, calendar: .current, origin: .demo)

        var views: [(String, AnyView)] = [
            ("00-marca", AnyView(HalsynCard { HStack(spacing: 24) { HalsynLogo(.vertical, height: 120); HalsynSymbol().frame(height: 60); HalsynLogo(.compact, height: 28) } })),
            ("00-anillos", AnyView(HalsynCard { HStack(spacing: 24) { HalsynScoreRing(score: 82, caption: "Bien").frame(width: 150); HalsynScoreRing(score: 37, lineWidth: 8).frame(width: 90) } })),
            ("01-recuperacion", AnyView(RecoveryCard(estimate: recovery.last, history: recovery))),
            ("02-anoche", AnyView(LastNightCard(night: night, targetHours: 8))),
            ("03-noches", AnyView(HalsynCard { HalsynSleepScheduleChart(nights: nights, targetHours: 8) })),
            ("03b-sueno", AnyView(HalsynCard { HalsynTrendChart(values: nights.map { DailyValue(day: $0.day, value: $0.asleep / 3600) }, title: "Sueño", style: .bar, target: 8, format: { sleepText($0 * 3600) }).frame(height: 220) })),
            ("04-hrv", AnyView(BaselineTrendCard(title: "Variabilidad cardíaca (HRV)", eyebrow: "PULS", series: hrv, unit: "ms", explanation: "Ejemplo"))),
            ("05-pasos", AnyView(HalsynCard { HalsynTrendChart(values: steps.values, title: "Pasos", style: .bar, target: 8000, unit: "pasos").frame(height: 210) })),
            ("06-puntuacion", AnyView(HalsynCard { HalsynTrendChart(values: scores.map { DailyValue(day: $0.day, value: Double($0.value)) }, title: "Puntuación", yDomain: 0...100, usualRange: usualRange(scores.map { Double($0.value) })).frame(height: 230) })),
        ]
        // Gráfico en vivo del reloj con una carrera sintética (fondo negro, tamaño de Apple Watch).
        let pace = (0..<300).map { LiveSample(elapsed: Double($0) * 5, value: 300 + 18 * sin(Double($0) / 14) + Double($0 % 7)) }
        let pulse = (0..<300).map { LiveSample(elapsed: Double($0) * 5, value: 140 + 12 * sin(Double($0) / 20)) }
        views.append(("11-reloj-ritmo", AnyView(
            HalsynLiveRunChart(paceSamples: pace, heartRateSamples: pulse, averagePace: Pace(secondsPerKilometer: 302), currentPace: Pace(secondsPerKilometer: 291), heartRate: 148, paceTarget: PaceRange(fastest: 290, slowest: 310))
                .frame(width: 198, height: 220)
                .padding(8)
                .background(Color.black)
        )))
        views.append(("12-reloj-zona", AnyView(HalsynZoneGauge(zone: 3).frame(width: 180).padding(12).background(Color.black))))
        // Análisis de una carrera demo.
        if let workout = await provider.recentWorkouts(limit: 1).first {
            let detail = await provider.workoutDetail(for: workout)
            if let insights = RunAnalyzer.analyze(route: detail.route, heartRate: detail.heartRate) {
                views.append(("14-carrera-analisis", AnyView(RunAnalysisCard(insights: insights, unitSystem: .metric))))
                views.append(("15-carrera-perfil", AnyView(RunProfileChart(insights: insights, unitSystem: .metric))))
            }
            if let comparison = RunAnalyzer.compare(workout, with: await provider.recentWorkouts(limit: 60)) {
                views.append(("16-carrera-comparacion", AnyView(SimilarRunsCard(comparison: comparison, unitSystem: .metric))))
            }
        }
        // Referencias por edad con las tablas reales (FRIEND 2015 y NHANES).
        if let vo2 = ReferencePercentileEngine.position(of: 46, metric: .vo2Max, age: 35, sex: .male),
           let resting = ReferencePercentileEngine.position(of: 49, metric: .restingHeartRate, age: 45, sex: .female) {
            views.append(("13-referencia", AnyView(HalsynCard {
                VStack(alignment: .leading, spacing: 24) {
                    HalsynReferenceStrip(position: vo2, unit: "mL/kg/min", format: { HalsynFormat.decimal($0, fractionDigits: 1) })
                    HalsynReferenceStrip(position: resting, unit: "lpm", format: { HalsynFormat.integer($0) })
                }
            })))
        }
        if let trend = report.trends.first {
            views.append(("07-cambio", AnyView(TrendInsightCard(insight: trend))))
        }
        for (index, relation) in report.relationships.prefix(2).enumerated() {
            views.append(("08-patron-\(index)", AnyView(RelationshipInsightCard(insight: relation))))
        }
        if let weekday = report.weekdays.first {
            views.append(("09-semana", AnyView(WeekdayInsightCard(insight: weekday))))
        }
        if !report.records.isEmpty {
            views.append(("10-records", AnyView(RecordsCard(records: report.records))))
        }
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
                // Algunas vistas con controles de UIKit no se pueden renderizar: se omiten.
                guard let data = renderer.uiImage?.pngData() else { continue }
                try data.write(to: directory.appendingPathComponent("\(name)-\(scheme == .dark ? "oscuro" : "claro").png"))
            }
        }
    }
}
