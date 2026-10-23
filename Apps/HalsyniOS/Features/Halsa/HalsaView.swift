import HalsynCore
import HalsynDesign
import SwiftUI

/// Datos que necesita el dashboard HÄLSA, cargados de una sola vez.
struct HalsaSnapshot: Sendable {
    var score: DailyScore?
    var recovery: DailyScore?
    var metrics: [MetricDisplay] = []
    var stepsTrend: [DailyValue] = []
    /// Primer objetivo del usuario y su progreso.
    var goal: (definition: GoalDefinition, progress: GoalProgress)?
    var lastWorkout: WorkoutSummary?
    var summary: [SummaryStatement] = []

    static let dashboardMetrics: [MetricKind] = [.sleepDuration, .restingHeartRate, .heartRateVariability, .steps, .activeEnergy, .exerciseTime]

    static func load(from provider: any HealthDataProviding, unitSystem: UnitSystem, goals: [GoalDefinition] = [], today: Date = .now) async -> HalsaSnapshot {
        var snapshot = HalsaSnapshot()
        snapshot.score = await provider.dailyScore(on: today)
        snapshot.recovery = await provider.recoveryScore(on: today)
        for kind in dashboardMetrics {
            snapshot.metrics.append(MetricDisplay(await provider.latest(kind, on: today), kind: kind, unitSystem: unitSystem))
        }
        snapshot.stepsTrend = await provider.dailySeries(.steps, days: 7, endingOn: today).values
        if let first = goals.first {
            let data = await provider.goalData(for: [first], endingOn: today, calendar: .current)
            snapshot.goal = (first, GoalEvaluator(calendar: .current).progress(first, data: data, now: today))
        }
        snapshot.lastWorkout = await provider.recentWorkouts(limit: 1).first
        snapshot.summary = await provider.dailySummary(on: today, calendar: .current)
        return snapshot
    }
}

enum HalsaDestination: Hashable {
    case vila
    case mal
    case history
    case score(DailyScore)
    case metric(MetricKind)
}

struct HalsaView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.userNameKey) private var userName = ""
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var snapshot: HalsaSnapshot?

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        NavigationStack {
            HalsynScreen {
                header
                if let snapshot {
                    scoreCard(snapshot)
                    summaryCard(snapshot)
                    if !model.isDemo && snapshot.metrics.contains(where: { $0.value == nil }) {
                        HealthAccessHint()
                    }
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
                case .history: HistoryView()
                case .score(let score): ScoreDetailView(score: score)
                case .metric(let kind): MetricDetailView(kind: kind)
                }
            }
            .task(id: "\(unitSystem.rawValue)|\(model.reloadKey)|\(GoalStore.shared.goals.hashValue)") {
                snapshot = await HalsaSnapshot.load(from: model.provider, unitSystem: unitSystem, goals: GoalStore.shared.goals)
            }
            .sheet(isPresented: Binding(get: { model.isShowingDailySummary }, set: { model.isShowingDailySummary = $0 })) {
                DailySummaryView()
            }
            .refreshable {
                snapshot = await HalsaSnapshot.load(from: model.provider, unitSystem: unitSystem, goals: GoalStore.shared.goals)
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
                Button {
                    model.selectedTab = .profile
                } label: {
                    ProfileAvatar(size: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Perfil"))
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
        let name = userName.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        switch (Calendar.current.component(.hour, from: .now), name.isEmpty) {
        case (5..<13, true): return "Buenos días"
        case (13..<20, true): return "Buenas tardes"
        case (_, true): return "Buenas noches"
        case (5..<13, false): return "Buenos días, \(name)"
        case (13..<20, false): return "Buenas tardes, \(name)"
        default: return "Buenas noches, \(name)"
        }
    }

    private func scoreCard(_ snapshot: HalsaSnapshot) -> some View {
        HalsynCard {
            VStack(spacing: HalsynSpacing.m) {
                HStack {
                    Text(verbatim: HalsynModule.halsa.brandName).halsynEyebrowStyle()
                    Spacer()
                    NavigationLink(value: HalsaDestination.history) {
                        Label("Historial", systemImage: "calendar")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynAccentText)
                    }
                }
                if let score = snapshot.score {
                    NavigationLink(value: HalsaDestination.score(score)) {
                        HalsynScoreRing(score: score.value, caption: score.band.title)
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Muestra el desglose de la puntuación"))
                    if let change = score.weeklyChange {
                        HalsynStatusIndicator(change >= 0 ? .positive : .neutral, text: String(localized: "\(change.formatted(.number.sign(strategy: .always()))) frente a tu media semanal"))
                    }
                    if let factors = score.breakdown?.factors.prefix(3), !factors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(factors.enumerated()), id: \.offset) { _, factor in
                                ScoreFactorRow(factor: factor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NavigationLink(value: HalsaDestination.score(score)) {
                        Text("Ver desglose")
                            .font(.halsynCaption.weight(.semibold))
                            .foregroundStyle(.halsynAccentText)
                    }
                    DataOriginFootnote(origin: score.origin, extra: "Estimación de bienestar provisional, no clínica.")
                } else {
                    HalsynScoreRing(score: nil, caption: nil)
                        .frame(maxWidth: 220)
                    Text("Aún no hay datos suficientes para la puntuación de hoy. Se necesita al menos el 60 % de las dimensiones (sueño, corazón, movimiento, ejercicio y equilibrio).")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func summaryCard(_ snapshot: HalsaSnapshot) -> some View {
        if !snapshot.summary.isEmpty {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynSectionHeader(Calendar.current.component(.hour, from: .now) >= 18 ? "Resumen del día" : "Tu día hasta ahora")
                    DailySummaryList(statements: snapshot.summary)
                }
            }
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
                HalsynTrendChart(values: snapshot.stepsTrend, title: "Pasos", style: .bar, target: HealthScoreConfiguration().stepsReference, unit: "pasos")
                    .frame(height: 210)
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
        if let goal = snapshot.goal {
            NavigationLink(value: HalsaDestination.mal) {
                HalsynCard {
                    HStack(spacing: HalsynSpacing.m) {
                        GoalRing(fraction: goal.progress.fraction, completed: goal.progress.isCompleted, systemImage: goal.definition.kind.systemImage)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: HalsynModule.mal.brandName).halsynEyebrowStyle()
                            Text(verbatim: GoalText.title(goal.definition, unit: .current, target: goal.progress.target))
                                .font(.halsynHeadline)
                                .foregroundStyle(.halsynPrimaryText)
                            Text(verbatim: GoalText.period(goal.definition.period))
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.halsynSecondaryText)
                            .accessibilityHidden(true)
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
