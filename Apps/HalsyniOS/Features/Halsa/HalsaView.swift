import HalsynCore
import HalsynDesign
import SwiftUI

/// Datos que necesita el dashboard HÄLSA, cargados de una sola vez.
struct HalsaSnapshot: Sendable {
    var score: DailyScore?
    var recovery: DailyScore?
    var metrics: [MetricDisplay] = []
    var stepsTrend: [DailyValue] = []
    var firstGoal: Goal?
    var lastWorkout: WorkoutSummary?

    static let dashboardMetrics: [MetricKind] = [.sleepDuration, .restingHeartRate, .heartRateVariability, .steps, .activeEnergy, .exerciseTime]

    static func load(from provider: any HealthDataProviding, unitSystem: UnitSystem, today: Date = .now) async -> HalsaSnapshot {
        var snapshot = HalsaSnapshot()
        snapshot.score = await provider.dailyScore(on: today)
        snapshot.recovery = await provider.recoveryScore(on: today)
        for kind in dashboardMetrics {
            snapshot.metrics.append(MetricDisplay(await provider.latest(kind, on: today), kind: kind, unitSystem: unitSystem))
        }
        snapshot.stepsTrend = await provider.dailySeries(.steps, days: 7, endingOn: today).values
        snapshot.firstGoal = await provider.goals().first
        snapshot.lastWorkout = await provider.recentWorkouts(limit: 1).first
        return snapshot
    }
}

enum HalsaDestination: Hashable {
    case vila
    case mal
    case metric(MetricKind)
}

struct HalsaView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var snapshot: HalsaSnapshot?

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        NavigationStack {
            HalsynScreen {
                header
                if let snapshot {
                    scoreCard(snapshot)
                    metricsGrid(snapshot)
                    recoveryCard(snapshot)
                    trendCard(snapshot)
                    springCard(snapshot)
                    goalCard(snapshot)
                    DataOriginFootnote(origin: model.isDemo ? .demo : nil, extra: "HÅLSYN ofrece estimaciones de bienestar. No es un dispositivo médico ni sustituye una evaluación profesional.")
                } else {
                    HalsynLoadingState()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HalsaDestination.self) { destination in
                switch destination {
                case .vila: VilaView()
                case .mal: MalView()
                case .metric(let kind): MetricDetailView(kind: kind)
                }
            }
            .task(id: unitSystem) {
                snapshot = await HalsaSnapshot.load(from: model.provider, unitSystem: unitSystem)
            }
            .refreshable {
                snapshot = await HalsaSnapshot.load(from: model.provider, unitSystem: unitSystem)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HStack {
                HalsynLogo(.compact, height: 28)
                Spacer()
                if model.isDemo {
                    HalsynDemoBadge()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.halsynTitle)
                    .foregroundStyle(.halsynPrimaryText)
                Text(verbatim: Date.now.halsynLongDay.capitalized)
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .padding(.top, HalsynSpacing.s)
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<13: "Buenos días"
        case 13..<20: "Buenas tardes"
        default: "Buenas noches"
        }
    }

    private func scoreCard(_ snapshot: HalsaSnapshot) -> some View {
        HalsynCard {
            VStack(spacing: HalsynSpacing.m) {
                HStack {
                    Text(verbatim: HalsynModule.halsa.brandName).halsynEyebrowStyle()
                    Spacer()
                    Text("Tu cuerpo hoy").font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
                }
                HalsynScoreRing(score: snapshot.score?.value, caption: snapshot.score?.band.title)
                    .frame(maxWidth: 220)
                if let change = snapshot.score?.weeklyChange {
                    HalsynStatusIndicator(change >= 0 ? .positive : .neutral, text: String(localized: "\(change.formatted(.number.sign(strategy: .always()))) frente a tu media semanal"))
                }
                if snapshot.score == nil {
                    Text("La puntuación necesita más datos. Se calculará cuando haya suficiente historial.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .multilineTextAlignment(.center)
                }
                DataOriginFootnote(origin: snapshot.score?.origin, extra: "Puntuación provisional de ejemplo. El motor real (HealthScoreEngine) llega en la Fase 3.")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func metricsGrid(_ snapshot: HalsaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            HalsynSectionHeader("Indicadores de hoy", eyebrow: "PULS · SÖMN · STEG")
            LazyVGrid(columns: columns, spacing: HalsynSpacing.s) {
                ForEach(snapshot.metrics, id: \.kind) { metric in
                    NavigationLink(value: HalsaDestination.metric(metric.kind)) {
                        HalsynMetricTile(
                            title: metric.kind.shortTitle,
                            systemImage: metric.kind.systemImage,
                            value: metric.value,
                            unit: metric.unit,
                            status: metric.status
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recoveryCard(_ snapshot: HalsaSnapshot) -> some View {
        NavigationLink(value: HalsaDestination.vila) {
            HalsynCard {
                HStack(spacing: HalsynSpacing.l) {
                    HalsynScoreRing(score: snapshot.recovery?.value, lineWidth: 8)
                        .frame(width: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: HalsynModule.vila.brandName).halsynEyebrowStyle()
                        Text("Recuperación estimada")
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text("Sueño, HRV y FC en reposo frente a tu rango habitual.")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.halsynSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func trendCard(_ snapshot: HalsaSnapshot) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tendencias", eyebrow: HalsynLexicon.steg.rawValue, actionTitle: "Ver INSIKT") {
                    model.selectedTab = .insikt
                }
                HalsynTrendChart(values: snapshot.stepsTrend, title: "Pasos", style: .bar)
                    .frame(height: 140)
            }
        }
    }

    private func springCard(_ snapshot: HalsaSnapshot) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Running", eyebrow: HalsynModule.spring.brandName)
                if let workout = snapshot.lastWorkout {
                    HStack {
                        HalsynMetric(title: "Última carrera", value: workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) }, unit: unitSystem.distanceUnitSymbol)
                        Spacer()
                        HalsynMetric(title: "Ritmo medio", value: workout.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                        Spacer()
                        HalsynMetric(title: "FC media", value: workout.averageHeartRate.map { String(Int($0)) }, unit: "lpm")
                    }
                }
                HalsynPrimaryButton("Ir a SPRING", systemImage: "figure.run") {
                    model.selectedTab = .spring
                }
            }
        }
    }

    @ViewBuilder
    private func goalCard(_ snapshot: HalsaSnapshot) -> some View {
        if let goal = snapshot.firstGoal {
            NavigationLink(value: HalsaDestination.mal) {
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                        HStack {
                            Text(verbatim: HalsynModule.mal.brandName).halsynEyebrowStyle()
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.halsynSecondaryText)
                                .accessibilityHidden(true)
                        }
                        Text(LocalizedStringKey(goal.title))
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        HalsynProgressBar(progress: goal.progress)
                        Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    HalsaView()
        .environment(AppModel())
}
