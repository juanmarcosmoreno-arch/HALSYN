import HalsynCore
import HalsynDesign
import SwiftUI

// MARK: - Historial

/// Un valor por día para ver cómo cambia la probabilidad. Se reinicia si
/// cambias la distancia, el tiempo objetivo o la fecha.
@MainActor
enum GoalProbabilityHistory {
    static let key = "halsyn.goalProbability.history"
    static let limit = 120

    private struct Entry: Codable {
        var day: Date
        var percent: Int
        var goal: String
    }

    private static var defaults: UserDefaults { .standard }

    static func signature(_ goal: PlanGoal) -> String {
        "\(goal.distance.rawValue)|\(Int(goal.goalTime ?? 0))|\(Int(goal.raceDate.timeIntervalSince1970 / 86_400))"
    }

    private static func load() -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// Guarda (o actualiza) el valor de hoy.
    static func record(_ probability: GoalProbability, goal: PlanGoal, today: Date = .now, calendar: Calendar = .current) {
        let signature = signature(goal)
        let day = calendar.startOfDay(for: today)
        var entries = load().filter { $0.goal == signature && $0.day != day }
        entries.append(Entry(day: day, percent: probability.percent, goal: signature))
        entries.sort { $0.day < $1.day }
        if let data = try? JSONEncoder().encode(Array(entries.suffix(limit))) {
            defaults.set(data, forKey: key)
        }
    }

    /// Cambio en puntos frente al valor de hace al menos 7 días.
    static func weeklyChange(current: GoalProbability, goal: PlanGoal, today: Date = .now, calendar: Calendar = .current) -> Int? {
        let signature = signature(goal)
        let limitDay = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: today)) ?? today
        guard let previous = load().last(where: { $0.goal == signature && $0.day <= limitDay }) else { return nil }
        return current.percent - previous.percent
    }
}

// MARK: - Textos y colores

enum GoalProbabilityText {
    static func color(_ level: GoalProbability.Level) -> Color {
        switch level {
        case .likely: .halsynPositive
        case .possible: .halsynCaution
        case .unlikely: .halsynAlert
        }
    }

    static func title(_ level: GoalProbability.Level) -> LocalizedStringKey {
        switch level {
        case .likely: "Probable"
        case .possible: "Posible, sin margen"
        case .unlikely: "Difícil por ahora"
        }
    }

    static func change(_ points: Int) -> String? {
        guard points != 0 else { return String(localized: "Igual que hace una semana") }
        let delta = abs(points)
        return points > 0
            ? String(localized: "▲ \(delta) puntos en una semana")
            : String(localized: "▼ \(delta) puntos en una semana")
    }
}

// MARK: - Ruedita

/// Anillo con el porcentaje: verde (70 % o más), amarillo (40–69 %) o rojo.
struct GoalProbabilityRing: View {
    let probability: GoalProbability
    var diameter: CGFloat = 64

    var body: some View {
        let tint = GoalProbabilityText.color(probability.level)
        let line = max(5, diameter / 10)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: probability.value)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(probability.percent) %")
                .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.halsynPrimaryText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(line)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.4), value: probability.value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Probabilidad de llegar al objetivo"))
        .accessibilityValue(Text(verbatim: "\(probability.percent) %"))
    }
}

// MARK: - Resumen (tarjeta del plan)

/// Ruedita con el porcentaje y una línea de qué la mueve.
struct GoalProbabilitySummary: View {
    let probability: GoalProbability
    let goal: PlanGoal

    var body: some View {
        HStack(alignment: .center, spacing: HalsynSpacing.m) {
            GoalProbabilityRing(probability: probability)
            VStack(alignment: .leading, spacing: 2) {
                Text("Probabilidad de llegar al objetivo")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                Text(GoalProbabilityText.title(probability.level))
                    .font(.halsynHeadline)
                    .foregroundStyle(GoalProbabilityText.color(probability.level))
                Text("Previsto el día de la carrera: \(HalsynFormat.duration(probability.projectedTime))")
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynPrimaryText)
                if let points = GoalProbabilityHistory.weeklyChange(current: probability, goal: goal), let text = GoalProbabilityText.change(points) {
                    Text(verbatim: text)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(points > 0 ? Color.halsynPositive : (points < 0 ? Color.halsynAlert : Color.halsynSecondaryText))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Lo que se muestra cuando todavía no se puede calcular.
struct GoalProbabilityMissing: View {
    let hasGoalTime: Bool
    let setGoal: () -> Void

    var body: some View {
        if hasGoalTime {
            Label("Para calcular la probabilidad de llegar al objetivo hace falta un test, una carrera o un entrenamiento de 3 km o más en las últimas 6 semanas.", systemImage: "percent")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button(action: setGoal) {
                Label("Pon un tiempo objetivo para ver la probabilidad de lograrlo", systemImage: "percent")
                    .font(.halsynCaption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Detalle (Tu objetivo)

/// Ruedita grande y lo que entra en el cálculo.
struct GoalProbabilityDetail: View {
    let probability: GoalProbability
    let estimate: FitnessEstimate
    let goal: PlanGoal

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HStack(spacing: HalsynSpacing.m) {
                GoalProbabilityRing(probability: probability, diameter: 88)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GoalProbabilityText.title(probability.level))
                        .font(.halsynHeadline)
                        .foregroundStyle(GoalProbabilityText.color(probability.level))
                    if let goalTime = goal.goalTime {
                        Text("de correr \(String(localized: String.LocalizationValue(goal.distance.title))) en \(HalsynFormat.duration(goalTime))")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    if let points = GoalProbabilityHistory.weeklyChange(current: probability, goal: goal), let text = GoalProbabilityText.change(points) {
                        Text(verbatim: text)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
            row("Tu forma hoy", value: RaceGoalText.vdot(probability.currentVDOT), detail: estimate.isFromTraining
                ? String(localized: "De tus mejores carreras recientes, en el plan o fuera de él")
                : String(localized: "De tu último test o carrera"))
            row("Sesiones cumplidas", value: complianceValue, detail: complianceDetail)
            row("Mejora esperada", value: "+" + HalsynFormat.decimal(probability.expectedGain, fractionDigits: 1), detail: String(localized: "En \(probability.trainingWeeks) semanas de entrenamiento, según cuánto cumples"))
            row("Prevista el día de la carrera", value: RaceGoalText.vdot(probability.projectedVDOT), detail: HalsynFormat.duration(probability.projectedTime))
            row("Pide el objetivo", value: RaceGoalText.vdot(probability.goalVDOT), detail: nil)
            ExpandableText("Cómo se calcula: tu forma de hoy (VDOT) más la mejora habitual de Daniels (1 punto cada 6 semanas) por las semanas que quedan, ajustada por las sesiones del plan que cumpliste en las últimas 4 semanas. La forma sale de tu último test o carrera, o de tu mejor esfuerzo de 3 km o más de las últimas 6 semanas, aunque no estuviera en el plan. La probabilidad es la de que tu forma el día de la carrera llegue a la que pide el objetivo, con un margen de error que crece si no hay un test reciente y por lo que puede pasar ese día. Ni optimista ni pesimista: con el objetivo justo en lo previsto da 50 %. Nunca baja de 3 % ni pasa de 97 %. Es una estimación orientativa, no una predicción segura; un test cada 6 semanas la hace más precisa.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var complianceValue: String {
        guard let compliance = probability.compliance else { return "—" }
        return "\(Int((compliance * 100).rounded())) %"
    }

    private var complianceDetail: String {
        guard probability.sessionsPlanned > 0 else { return String(localized: "Aún no hay sesiones pasadas: se asume lo habitual") }
        return String(localized: "\(probability.sessionsDone) de \(probability.sessionsPlanned) en las últimas 4 semanas")
    }

    private func row(_ title: LocalizedStringKey, value: String, detail: String?) -> some View {
        LabeledContent {
            Text(verbatim: value).monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(verbatim: detail)
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .font(.halsynCaption)
    }
}
