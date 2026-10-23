import HalsynCore
import HalsynDesign
import SwiftUI

enum WatchDestination: Hashable {
    case status
    case spring
    case recovery
    case summary
}

/// Pantalla inicial: estado del día y accesos rápidos. Iniciar una carrera debe
/// requerir el mínimo de toques.
struct WatchHomeView: View {
    let provider: any HealthDataProviding
    @State private var score: DailyScore?
    @State private var recovery: DailyScore?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        HStack {
                            HalsynSymbol().frame(height: 22)
                            Spacer()
                            if provider.mode == .demo {
                                Text("DEMO")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(HalsynPalette.cautionDark))
                                    .accessibilityLabel(Text("Datos de demostración"))
                            }
                        }
                        HalsynScoreRing(score: score?.value, caption: score?.band.title, lineWidth: 9)
                            .frame(maxWidth: 120)
                    }
                    .listRowBackground(Color.clear)
                }

                NavigationLink(value: WatchDestination.spring) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(verbatim: HalsynModule.spring.brandName).font(.headline)
                            Text("Iniciar carrera").font(.caption2).foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                        }
                    } icon: {
                        Image(systemName: "figure.run")
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(HalsynPalette.darkPrimary))
                )

                NavigationLink(value: WatchDestination.status) {
                    Label("Mi estado", systemImage: "heart.text.square")
                }
                NavigationLink(value: WatchDestination.recovery) {
                    Label {
                        HStack {
                            Text("Recuperación")
                            Spacer()
                            Text(verbatim: recovery.map { "\($0.value)" } ?? "—")
                                .foregroundStyle(Color(HalsynPalette.darkAccent))
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "moon")
                    }
                }
                NavigationLink(value: WatchDestination.summary) {
                    Label("Resumen diario", systemImage: "list.bullet.rectangle")
                }
            }
            .navigationTitle(Text(verbatim: HalsynBrand.name))
            .navigationDestination(for: WatchDestination.self) { destination in
                switch destination {
                case .status: WatchStatusView(provider: provider)
                case .spring: WatchSpringView()
                case .recovery: WatchRecoveryView(provider: provider)
                case .summary: WatchDailySummaryView(provider: provider)
                }
            }
            .containerBackground(HalsynGradients.deep, for: .navigation)
            .task {
                score = await provider.dailyScore(on: .now)
                recovery = await provider.recoveryScore(on: .now)
            }
        }
    }
}

/// Mi estado: indicadores fisiológicos de hoy.
struct WatchStatusView: View {
    let provider: any HealthDataProviding
    @State private var metrics: [MetricDisplay] = []

    var body: some View {
        List {
            ForEach(metrics, id: \.kind) { metric in
                HalsynWatchMetric(title: metric.kind.shortTitle, systemImage: metric.kind.systemImage, value: metric.value, unit: metric.unit)
            }
            if provider.mode == .demo {
                Text("Datos demo").font(.footnote).foregroundStyle(Color(HalsynPalette.cautionDark))
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.halsa.brandName))
        .task {
            var result: [MetricDisplay] = []
            for kind in [MetricKind.restingHeartRate, .heartRateVariability, .sleepDuration, .vo2Max] {
                result.append(MetricDisplay(await provider.latest(kind, on: .now), kind: kind))
            }
            metrics = result
        }
    }
}

/// Recuperación estimada y sus componentes.
struct WatchRecoveryView: View {
    let provider: any HealthDataProviding
    @State private var recovery: DailyScore?
    @State private var metrics: [MetricDisplay] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HalsynScoreRing(score: recovery?.value, caption: "Recuperación", lineWidth: 9)
                    .frame(maxWidth: 130)
                ForEach(metrics, id: \.kind) { metric in
                    HalsynWatchMetric(title: metric.kind.shortTitle, systemImage: metric.kind.systemImage, value: metric.value, unit: metric.unit)
                }
                Text("Estimación orientativa, no médica.")
                    .font(.footnote)
                    .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.vila.brandName))
        .task {
            recovery = await provider.recoveryScore(on: .now)
            var result: [MetricDisplay] = []
            for kind in [MetricKind.sleepDuration, .heartRateVariability, .restingHeartRate] {
                result.append(MetricDisplay(await provider.latest(kind, on: .now), kind: kind))
            }
            metrics = result
        }
    }
}

/// Resumen de actividad del día.
struct WatchDailySummaryView: View {
    let provider: any HealthDataProviding
    @State private var metrics: [MetricDisplay] = []

    var body: some View {
        List {
            ForEach(metrics, id: \.kind) { metric in
                HalsynWatchMetric(title: metric.kind.shortTitle, systemImage: metric.kind.systemImage, value: metric.value, unit: metric.unit)
            }
        }
        .navigationTitle("Hoy")
        .task {
            var result: [MetricDisplay] = []
            for kind in [MetricKind.steps, .walkingRunningDistance, .activeEnergy, .exerciseTime] {
                result.append(MetricDisplay(await provider.latest(kind, on: .now), kind: kind))
            }
            metrics = result
        }
    }
}

#Preview {
    WatchHomeView(provider: DemoHealthDataProvider())
}
