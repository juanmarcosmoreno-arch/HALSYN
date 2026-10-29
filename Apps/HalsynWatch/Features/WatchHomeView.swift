import HalsynCore
import HalsynDesign
import SwiftUI
import WidgetKit

enum WatchDestination: Hashable {
    case status
    case spring
    case cykel
    case permissions
    case recovery
    case summary
}

/// Pantalla inicial: estado del día y accesos rápidos. Iniciar una carrera debe
/// requerir el mínimo de toques.
struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model
    @Environment(WorkoutManager.self) private var workout
    /// Falta algún permiso (Salud o ubicación): se muestra arriba.
    @State private var permissionsPending = false
    @State private var score: DailyScore?
    @State private var recovery: DailyScore?
    @State private var isConnecting = false
    @State private var path: [WatchDestination] = []

    private var provider: any HealthDataProviding { model.provider }
    private var phoneSnapshot: WidgetSnapshot? { RunSettingsStore.shared.phoneSnapshot }

    var body: some View {
        NavigationStack(path: $path) {
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
                        HalsynScoreRing(score: score?.value, lineWidth: 9)
                            .frame(maxWidth: 120)
                    }
                    .listRowBackground(Color.clear)
                }

                if permissionsPending {
                    NavigationLink(value: WatchDestination.permissions) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Permisos").font(.headline)
                                Text("Falta permitir Salud o ubicación").font(.caption2).foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.shield")
                                .foregroundStyle(Color(HalsynPalette.cautionDark))
                        }
                    }
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

                NavigationLink(value: WatchDestination.cykel) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(verbatim: HalsynModule.cykel.brandName).font(.headline)
                            Text("Salir en bici").font(.caption2).foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                        }
                    } icon: {
                        Image(systemName: "bicycle")
                    }
                }

                if model.isDemo {
                    Button {
                        Task {
                            isConnecting = true
                            await model.connectAppleHealth()
                            isConnecting = false
                        }
                    } label: {
                        Label(isConnecting ? LocalizedStringKey("Conectando…") : LocalizedStringKey("Conectar Apple Health"), systemImage: "heart.text.square")
                    }
                    .disabled(isConnecting)
                }

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
                if !permissionsPending {
                    NavigationLink(value: WatchDestination.permissions) {
                        Label("Permisos", systemImage: "checkmark.shield")
                    }
                }
            }
            .navigationTitle(Text(verbatim: HalsynBrand.name))
            .navigationDestination(for: WatchDestination.self) { destination in
                switch destination {
                case .status: WatchStatusView(provider: provider, reloadKey: model.reloadKey)
                case .spring: WatchSpringView()
                case .cykel: WatchCykelView()
                case .permissions: WatchPermissionsView()
                case .recovery: WatchRecoveryView(provider: provider, reloadKey: model.reloadKey)
                case .summary: WatchDailySummaryView(provider: provider, reloadKey: model.reloadKey)
                }
            }
            .containerBackground(HalsynGradients.deep, for: .navigation)
            .task(id: "\(model.reloadKey)|\(workout.locationAuthorization.rawValue)|\(path.count)") {
                let location = workout.locationAuthorization
                let health = await workout.healthNeedsAuthorization()
                permissionsPending = health || location == .notDetermined || workout.locationDenied
            }
            .task(id: "\(model.reloadKey)|\(phoneSnapshot?.updatedAt.timeIntervalSince1970 ?? 0)") {
                // Si el iPhone ya calculó la puntuación de hoy, se usa esa: tiene todo el
                // historial. El cálculo propio queda para cuando no hay iPhone cerca.
                if let phone = phoneSnapshot, phone.isFromToday(.now, calendar: .current), phone.isDemo == model.isDemo {
                    score = phone.score.map { DailyScore(day: .now, value: $0, weeklyChange: nil, origin: .derived(engine: "iPhone")) }
                    recovery = phone.recovery.map { DailyScore(day: .now, value: $0, weeklyChange: nil, origin: .derived(engine: "iPhone")) }
                } else {
                    score = await provider.dailyScore(on: .now)
                    recovery = await provider.recoveryScore(on: .now)
                    publishForComplications()
                }
            }
            // Complicación "Correr": halsyn://spring abre SPRING directamente (halsyn://cykel, CYKEL).
            .onOpenURL { url in
                switch url.host {
                case "spring": path = [.spring]
                case "cykel": path = [.cykel]
                default: path = []
                }
            }
        }
    }
}

extension WatchHomeView {
    /// Deja la puntuación y la recuperación para las complicaciones del reloj.
    fileprivate func publishForComplications() {
        guard let defaults = WidgetSnapshotStore.sharedDefaults() else { return }
        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            score: score?.value,
            scoreBand: score.map { NSLocalizedString($0.band.title, comment: "") },
            recovery: recovery?.value,
            isDemo: model.isDemo
        )
        WidgetSnapshotStore.save(snapshot, to: defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Mi estado: indicadores fisiológicos de hoy.
struct WatchStatusView: View {
    let provider: any HealthDataProviding
    let reloadKey: String
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
        .task(id: reloadKey) {
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
    let reloadKey: String
    @State private var recovery: DailyScore?
    @State private var metrics: [MetricDisplay] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HalsynScoreRing(score: recovery?.value, lineWidth: 9)
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
        .task(id: reloadKey) {
            if let phone = RunSettingsStore.shared.phoneSnapshot, phone.isFromToday(.now, calendar: .current),
               phone.isDemo == (provider.mode == .demo), let value = phone.recovery {
                recovery = DailyScore(day: .now, value: value, weeklyChange: nil, origin: .derived(engine: "iPhone"))
            } else {
                recovery = await provider.recoveryScore(on: .now)
            }
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
    let reloadKey: String
    @State private var metrics: [MetricDisplay] = []

    var body: some View {
        List {
            ForEach(metrics, id: \.kind) { metric in
                HalsynWatchMetric(title: metric.kind.shortTitle, systemImage: metric.kind.systemImage, value: metric.value, unit: metric.unit)
            }
        }
        .navigationTitle("Hoy")
        .task(id: reloadKey) {
            var result: [MetricDisplay] = []
            for kind in [MetricKind.steps, .walkingRunningDistance, .activeEnergy, .exerciseTime] {
                result.append(MetricDisplay(await provider.latest(kind, on: .now), kind: kind))
            }
            metrics = result
        }
    }
}

#Preview {
    WatchHomeView()
        .environment(WatchModel())
        .environment(WorkoutManager.shared)
}
