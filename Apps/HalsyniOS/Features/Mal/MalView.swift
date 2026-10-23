import HalsynCore
import HalsynDesign
import SwiftUI

/// MÅL — objetivos propios con progreso real, ritmo, racha, historial y recordatorios.
struct MalView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var data: GoalData?
    @State private var editing: GoalDefinition?
    @State private var creating = false
    private var store: GoalStore { .shared }
    private let evaluator = GoalEvaluator(calendar: .current)

    var body: some View {
        HalsynScreen {
            ModuleHeader(module: .mal, isDemo: model.isDemo)
                .padding(.top, HalsynSpacing.s)

            if let data {
                if store.goals.isEmpty {
                    HalsynCard {
                        HalsynEmptyState(systemImage: "target", title: "Sin objetivos todavía", message: "Elige uno de los sugeridos o crea el tuyo. El progreso se calcula con tus datos de Apple Health.")
                    }
                } else {
                    ForEach(store.goals) { goal in
                        Button {
                            editing = goal
                        } label: {
                            GoalCard(goal: goal, progress: evaluator.progress(goal, data: data, now: .now), history: evaluator.history(goal, data: data, now: .now, count: goal.period == .daily ? 14 : 8), streak: evaluator.streak(goal, data: data, now: .now), unit: unitSystem)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HalsynPrimaryButton("Nuevo objetivo", systemImage: "plus") {
                    creating = true
                }

                suggestions
                DataOriginFootnote(origin: model.isDemo ? .demo : nil, extra: "Los objetivos se guardan solo en este iPhone.")
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.mal.brandName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(model.reloadKey)-\(store.goals.map(\.id).hashValue)") {
            data = await model.provider.goalData(for: store.goals + GoalDefinition.templates, endingOn: .now, calendar: .current)
        }
        .sheet(isPresented: $creating) {
            GoalEditorView(goal: nil, data: data)
        }
        .sheet(item: $editing) { goal in
            GoalEditorView(goal: goal, data: data)
        }
    }

    /// Plantillas que el usuario aún no tiene.
    @ViewBuilder
    private var suggestions: some View {
        let existing = Set(store.goals.map { "\($0.kind.rawValue)-\($0.period.rawValue)" })
        let available = GoalDefinition.templates.filter { !existing.contains("\($0.kind.rawValue)-\($0.period.rawValue)") }
        if !available.isEmpty {
            HalsynSectionHeader("Sugerencias", eyebrow: HalsynModule.mal.brandName)
            VStack(spacing: HalsynSpacing.s) {
                ForEach(available) { template in
                    Button {
                        store.save(GoalDefinition(kind: template.kind, period: template.period, target: template.target))
                    } label: {
                        HStack(spacing: HalsynSpacing.m) {
                            Image(systemName: template.kind.systemImage)
                                .foregroundStyle(.halsynAccentText)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: GoalText.title(template, unit: unitSystem))
                                    .font(.halsynHeadline)
                                    .foregroundStyle(.halsynPrimaryText)
                                Text(verbatim: GoalText.period(template.period))
                                    .font(.halsynCaption)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.halsynAccent)
                                .accessibilityHidden(true)
                        }
                        .padding(HalsynSpacing.m)
                        .background(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).fill(Color.halsynSurface))
                        .overlay(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).strokeBorder(Color.halsynHairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Añadir objetivo"))
                }
            }
            Text("150 min semanales de actividad moderada es la recomendación de la OMS para adultos; 7–9 h de sueño, la recomendación general para adultos.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
    }
}

/// Tarjeta de un objetivo: anillo de progreso, ritmo, racha y últimos periodos.
struct GoalCard: View {
    let goal: GoalDefinition
    let progress: GoalProgress
    let history: [GoalPeriodResult]
    let streak: Int
    let unit: UnitSystem

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .center, spacing: HalsynSpacing.m) {
                    GoalRing(fraction: progress.fraction, completed: progress.isCompleted, systemImage: goal.kind.systemImage)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: GoalText.title(goal, unit: unit, target: progress.target))
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: "\(GoalText.value(progress.current, goal.kind, unit: unit)) / \(GoalText.value(progress.target, goal.kind, unit: unit))")
                            .font(.halsynCaption.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                        HStack(spacing: HalsynSpacing.xs) {
                            Text(verbatim: GoalText.period(goal.period))
                            if goal.reminder != nil {
                                Image(systemName: "bell.fill").accessibilityLabel(Text("Con recordatorio"))
                            }
                            if goal.progression != nil {
                                Image(systemName: "chart.line.uptrend.xyaxis").accessibilityLabel(Text("Aumento gradual"))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    }
                    Spacer(minLength: 0)
                    if streak > 1 {
                        VStack(spacing: 0) {
                            Image(systemName: "flame.fill").foregroundStyle(.halsynAccent)
                            Text(verbatim: "\(streak)")
                                .font(.halsynHeadline.monospacedDigit())
                                .foregroundStyle(.halsynPrimaryText)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Racha de \(streak)"))
                    }
                }
                paceLine
                if !history.isEmpty {
                    GoalHistoryStrip(history: history)
                }
            }
        }
    }

    @ViewBuilder
    private var paceLine: some View {
        switch progress.pace {
        case .completed:
            HalsynStatusIndicator(.positive, text: "Cumplido")
        case .ahead:
            HalsynStatusIndicator(.positive, text: "Vas por delante")
        case .onTrack:
            HalsynStatusIndicator(.neutral, text: "Vas al día")
        case .behind:
            if let needed = progress.neededPerRemainingDay {
                HalsynStatusIndicator(.caution, text: String(localized: "Te faltan \(GoalText.value(progress.remaining, goal.kind, unit: unit)): unos \(GoalText.value(needed, goal.kind, unit: unit)) al día"))
            } else {
                HalsynStatusIndicator(.caution, text: "Por debajo del objetivo")
            }
        case .missed:
            HalsynStatusIndicator(.caution, text: "No cumplido")
        case .noData:
            HalsynStatusIndicator(.neutral, text: "Sin datos todavía")
        }
    }
}

/// Anillo compacto de progreso con el icono del objetivo dentro.
struct GoalRing: View {
    let fraction: Double
    let completed: Bool
    let systemImage: String
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.halsynAccentSoft.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(Color.halsynChart, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: completed ? "checkmark" : systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.halsynAccentText)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// Últimos periodos: un punto por periodo, lleno si se cumplió.
struct GoalHistoryStrip: View {
    let history: [GoalPeriodResult]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(history) { result in
                Capsule()
                    .fill(result.isCompleted ? Color.halsynChart : (result.hasData ? Color.halsynChart.opacity(0.25) : Color.halsynHairline))
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cumplido \(history.filter(\.isCompleted).count) de los últimos \(history.count) periodos"))
    }
}

#Preview {
    NavigationStack { MalView() }
        .environment(AppModel())
}
