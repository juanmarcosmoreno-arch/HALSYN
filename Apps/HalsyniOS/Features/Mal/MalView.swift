import HalsynCore
import HalsynDesign
import SwiftUI

/// MÅL — objetivos. En la Fase 1 muestra objetivos de ejemplo; la creación,
/// edición y planificación llegan en la Fase 9.
struct MalView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @State private var goals: [Goal]?

    var body: some View {
        HalsynScreen {
            ModuleHeader(module: .mal, isDemo: model.isDemo)
                .padding(.top, HalsynSpacing.s)

            if let goals {
                if goals.isEmpty {
                    HalsynEmptyState(systemImage: "target", title: "Sin objetivos", message: "Cuando definas objetivos aparecerán aquí.")
                } else {
                    ForEach(goals) { goal in
                        goalCard(goal)
                    }
                }
                HalsynCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Crear y editar objetivos")
                                .font(.halsynHeadline)
                                .foregroundStyle(.halsynPrimaryText)
                            Text("Calendario, recordatorios opcionales y planes 5K–maratón.")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        Spacer()
                        PhaseTag(phase: 9)
                    }
                }
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.mal.brandName))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            goals = await model.provider.goals()
        }
    }

    private func goalCard(_ goal: Goal) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack {
                    Label(LocalizedStringKey(goal.period.title), systemImage: goal.metric.systemImage)
                        .halsynEyebrowStyle()
                    Spacer()
                    if goal.isCompleted {
                        HalsynStatusIndicator(.positive, text: "Cumplido")
                    }
                }
                Text(LocalizedStringKey(goal.title))
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                HalsynProgressBar(progress: goal.progress)
                HStack {
                    Text("\(formatted(goal.current, goal.metric)) / \(formatted(goal.target, goal.metric)) \(Text(LocalizedStringKey(unit(goal.metric))))")
                    Spacer()
                    Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                }
                .font(.halsynCaption.monospacedDigit())
                .foregroundStyle(.halsynSecondaryText)
                DataOriginFootnote(origin: goal.origin)
            }
        }
    }

    private func formatted(_ value: Double, _ metric: MetricKind) -> String {
        switch metric {
        case .walkingRunningDistance:
            HalsynFormat.decimal(value / unitSystem.metersPerDistanceUnit, fractionDigits: 1)
        case .sleepDuration:
            HalsynFormat.decimal(value, fractionDigits: 1)
        default:
            HalsynFormat.integer(value)
        }
    }

    private func unit(_ metric: MetricKind) -> String {
        metric == .walkingRunningDistance ? unitSystem.distanceUnitSymbol : metric.unit.symbol
    }
}

#Preview {
    NavigationStack { MalView() }
        .environment(AppModel())
}
