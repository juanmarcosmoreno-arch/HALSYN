import HalsynCore
import HalsynDesign
import SwiftUI

// MARK: - Historial

/// Tiempo previsto el día de la carrera, uno por día, para ver cómo cambia.
/// Se reinicia si cambias la distancia, el tiempo objetivo o la fecha.
@MainActor
enum GoalProbabilityHistory {
    static let key = "halsyn.goalProbability.history.v2"
    static let limit = 120

    private struct Entry: Codable {
        var day: Date
        var projected: TimeInterval
        var goal: String
        /// Valor del modelo sin calibrar (para la calibración posterior).
        var modelValue: Double?
    }

    private static var defaults: UserDefaults { .standard }

    static func signature(_ goal: PlanGoal) -> String {
        "\(goal.distance.rawValue)|\(Int(goal.goalTime ?? 0))|\(Int(goal.raceDate.timeIntervalSince1970 / 86_400))"
    }

    private static func load() -> [Entry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func record(_ probability: GoalProbability, goal: PlanGoal, today: Date = .now, calendar: Calendar = .current) {
        let signature = signature(goal)
        let day = calendar.startOfDay(for: today)
        var entries = load().filter { $0.goal == signature && $0.day != day }
        entries.append(Entry(day: day, projected: probability.projectedTime, goal: signature, modelValue: probability.modelValue))
        entries.sort { $0.day < $1.day }
        if let data = try? JSONEncoder().encode(Array(entries.suffix(limit))) {
            defaults.set(data, forKey: key)
        }
    }

    /// Valor del modelo de una semana antes de la carrera (o el más cercano anterior).
    static func modelValue(before raceDate: Date, goal: PlanGoal, calendar: Calendar = .current) -> Double? {
        let signature = signature(goal)
        let limit = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: raceDate)) ?? raceDate
        let entries = load().filter { $0.goal == signature && $0.modelValue != nil }
        return (entries.last { $0.day <= limit } ?? entries.first)?.modelValue
    }

    /// Segundos que mejoró (negativo) o empeoró el tiempo previsto frente a hace al menos 7 días.
    static func weeklyChange(current: GoalProbability, goal: PlanGoal, today: Date = .now, calendar: Calendar = .current) -> TimeInterval? {
        let signature = signature(goal)
        let limitDay = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: today)) ?? today
        guard let previous = load().last(where: { $0.goal == signature && $0.day <= limitDay }) else { return nil }
        return current.projectedTime - previous.projected
    }
}

// MARK: - Textos y colores

enum GoalProbabilityText {
    static func color(_ category: GoalProbability.Category) -> Color {
        switch category {
        case .veryLikely: .halsynPositive
        case .achievable: .halsynAccentText
        case .demanding: .halsynCaution
        case .unrealistic: .halsynAlert
        }
    }

    static func titleText(_ category: GoalProbability.Category) -> String {
        switch category {
        case .veryLikely: String(localized: "Muy probable")
        case .achievable: String(localized: "Alcanzable")
        case .demanding: String(localized: "Exigente")
        case .unrealistic: String(localized: "Poco realista por ahora")
        }
    }

    static func symbol(_ category: GoalProbability.Category) -> String {
        switch category {
        case .veryLikely: "checkmark"
        case .achievable: "flag.checkered"
        case .demanding: "flame"
        case .unrealistic: "exclamationmark"
        }
    }

    /// Cuánto se llena la ruedita: es una escala de categorías, no un porcentaje.
    static func fill(_ category: GoalProbability.Category) -> Double {
        switch category {
        case .veryLikely: 1
        case .achievable: 0.75
        case .demanding: 0.5
        case .unrealistic: 0.25
        }
    }

    static func change(_ seconds: TimeInterval) -> String {
        let delta = Int(abs(seconds).rounded())
        guard delta >= 5 else { return String(localized: "Previsto igual que hace una semana") }
        let text = HalsynFormat.duration(TimeInterval(delta))
        return seconds < 0
            ? String(localized: "Previsto \(text) más rápido que hace una semana")
            : String(localized: "Previsto \(text) más lento que hace una semana")
    }

    static func range(_ range: ClosedRange<TimeInterval>) -> String {
        "\(HalsynFormat.duration(range.lowerBound))–\(HalsynFormat.duration(range.upperBound))"
    }

    static func confidence(_ confidence: PerformanceAssessment.Confidence) -> String {
        switch confidence {
        case .high: String(localized: "Confianza alta")
        case .medium: String(localized: "Confianza media")
        case .low: String(localized: "Confianza baja")
        }
    }

    /// Frase de cada factor, con el dato que la respalda.
    static func factor(_ factor: GoalProbability.Factor, unit: UnitSystem) -> String {
        switch factor.kind {
        case .gap:
            let points = HalsynFormat.decimal(abs(factor.value), fractionDigits: 1)
            if factor.value <= 0 { return String(localized: "Tu forma de hoy ya alcanza para el objetivo.") }
            let usual = HalsynFormat.decimal(factor.reference ?? 0, fractionDigits: 1)
            return factor.effect == .hinders
                ? String(localized: "Te faltan \(points) puntos de VDOT; la mejora habitual en el tiempo que queda es de unos \(usual).")
                : String(localized: "Te faltan \(points) puntos de VDOT, dentro de la mejora habitual (\(usual)) para el tiempo que queda.")
        case .compliance:
            let percent = "\(Int((factor.value * 100).rounded())) %"
            switch factor.effect {
            case .favors: return String(localized: "Cumpliste el \(percent) de las sesiones de las últimas 4 semanas.")
            case .neutral: return String(localized: "Cumpliste el \(percent) de las sesiones de las últimas 4 semanas: algo menos de lo ideal.")
            case .hinders: return String(localized: "Cumpliste solo el \(percent) de las sesiones de las últimas 4 semanas: la mejora esperada baja.")
            }
        case .trend:
            let perWeek = HalsynFormat.decimal(abs(factor.value), fractionDigits: 2)
            switch factor.effect {
            case .favors: return String(localized: "Tu forma viene mejorando (+\(perWeek) VDOT por semana).")
            case .hinders: return String(localized: "Tu forma viene bajando (−\(perWeek) VDOT por semana).")
            case .neutral: return String(localized: "Tu forma está estable en las últimas semanas.")
            }
        case .time:
            let weeksText = String(Int(factor.value))
            let minimumText = String(Int(factor.reference ?? 0))
            return factor.effect == .favors
                ? String(localized: "Quedan \(weeksText) semanas: tiempo suficiente para esta distancia.")
                : String(localized: "Quedan \(weeksText) semanas; para esta distancia se suelen recomendar \(minimumText) o más.")
        case .volume:
            let weekly = SessionText.distance(factor.value, unit: unit)
            let minimum = SessionText.distance(factor.reference ?? 0, unit: unit)
            switch factor.effect {
            case .favors: return String(localized: "Corres \(weekly) por semana, suficiente para esta distancia.")
            case .neutral: return String(localized: "Corres \(weekly) por semana; para esta distancia conviene acercarse a \(minimum).")
            case .hinders: return String(localized: "Corres \(weekly) por semana, poco para esta distancia (se recomienda \(minimum) o más).")
            }
        case .confidence:
            switch factor.effect {
            case .favors: return String(localized: "La estimación es confiable: tienes pruebas recientes y coherentes.")
            case .neutral: return String(localized: "La estimación es razonable, pero un test reciente la haría más precisa.")
            case .hinders: return String(localized: "La estimación tiene baja confianza: faltan pruebas recientes. Un test lo resuelve.")
            }
        }
    }
}

// MARK: - Ruedita

/// Ruedita de la factibilidad: color y llenado por categoría (no es un porcentaje).
struct GoalProbabilityRing: View {
    let probability: GoalProbability
    var diameter: CGFloat = 64

    var body: some View {
        let tint = GoalProbabilityText.color(probability.category)
        let line = max(5, diameter / 10)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: GoalProbabilityText.fill(probability.category))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: GoalProbabilityText.symbol(probability.category))
                .font(.system(size: diameter * 0.3, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Factibilidad del objetivo"))
        .accessibilityValue(Text(verbatim: GoalProbabilityText.titleText(probability.category)))
    }
}

// MARK: - Resumen (tarjeta del plan)

struct GoalProbabilitySummary: View {
    let probability: GoalProbability
    let goal: PlanGoal

    var body: some View {
        HStack(alignment: .center, spacing: HalsynSpacing.m) {
            GoalProbabilityRing(probability: probability)
            VStack(alignment: .leading, spacing: 2) {
                Text("Objetivo")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                HStack(spacing: 6) {
                    Text(verbatim: GoalProbabilityText.titleText(probability.category))
                        .font(.halsynHeadline)
                        .foregroundStyle(GoalProbabilityText.color(probability.category))
                    // El porcentaje solo con calibración comprobada (5 objetivos o más).
                    if GoalCalibration.allowsPercentage(FitnessStore.shared.goalOutcomes) {
                        Text(verbatim: "\(Int((probability.modelValue * 100).rounded())) %")
                            .font(.halsynCaption.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
                Text("Hoy \(HalsynFormat.duration(probability.currentTime)) · día de la carrera \(HalsynFormat.duration(probability.projectedTime))")
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynPrimaryText)
                Text("Rango orientativo: \(GoalProbabilityText.range(probability.projectedRange))")
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynPrimaryText)
                if let seconds = GoalProbabilityHistory.weeklyChange(current: probability, goal: goal) {
                    Text(verbatim: GoalProbabilityText.change(seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(seconds < -4 ? Color.halsynPositive : (seconds > 4 ? Color.halsynAlert : Color.halsynSecondaryText))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct GoalProbabilityMissing: View {
    let hasGoalTime: Bool
    let setGoal: () -> Void

    var body: some View {
        if hasGoalTime {
            Label("Para estimar si llegas al objetivo hace falta un test, una competición o un entrenamiento a tope (pulso alto sostenido) de 3 km o más en las últimas 6 semanas.", systemImage: "stopwatch")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button(action: setGoal) {
                Label("Pon un tiempo objetivo para ver si es alcanzable", systemImage: "flag.checkered")
                    .font(.halsynCaption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Detalle (Tu objetivo)

/// Factibilidad con lo que acerca y aleja el objetivo, y cómo se calcula.
struct GoalProbabilityDetail: View {
    let probability: GoalProbability
    let performance: PerformanceAssessment
    let goal: PlanGoal
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            HStack(spacing: HalsynSpacing.m) {
                GoalProbabilityRing(probability: probability, diameter: 80)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: GoalProbabilityText.titleText(probability.category))
                        .font(.halsynHeadline)
                        .foregroundStyle(GoalProbabilityText.color(probability.category))
                    if let goalTime = goal.goalTime {
                        Text("Objetivo \(HalsynFormat.duration(goalTime)) · previsto \(HalsynFormat.duration(probability.projectedTime))")
                            .font(.halsynCaption.monospacedDigit())
                    }
                    Text("Rango probable el día de la carrera: \(GoalProbabilityText.range(probability.projectedRange))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                    Text(verbatim: GoalProbabilityText.confidence(probability.confidence))
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
            factorList("A favor", effect: .favors, symbol: "arrow.up.circle.fill", tint: .halsynPositive)
            factorList("En contra", effect: .hinders, symbol: "arrow.down.circle.fill", tint: .halsynAlert)
            factorList("Neutral", effect: .neutral, symbol: "minus.circle", tint: .halsynSecondaryText)
            ExpandableText("Cómo se calcula: tu forma de hoy sale de tus tests, competiciones y entrenamientos a tope (los más recientes pesan más; uno que no encaja con los demás pesa menos). Se le suma la mejora esperada hasta la carrera: la mitad según la pauta prudente de Daniels (1 punto de VDOT cada 6 semanas) y la mitad según tu tendencia real, ajustada por cuánto cumples el plan. El rango orientativo suma la incertidumbre de tu forma, de la mejora, del tiempo que falta y del día de la carrera; está pensado para contener 8 de cada 10 resultados, pero eso aún no se comprobó con tus datos. Se muestra una categoría y no un porcentaje porque todavía no hay resultados reales tuyos para comprobar que esos porcentajes acierten. No es una garantía.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func factorList(_ title: LocalizedStringKey, effect: GoalProbability.Factor.Effect, symbol: String, tint: Color) -> some View {
        let factors = probability.factors.filter { $0.effect == effect }
        if !factors.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.halsynSecondaryText)
                ForEach(factors) { factor in
                    Label {
                        Text(verbatim: GoalProbabilityText.factor(factor, unit: unitSystem))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: symbol).foregroundStyle(tint)
                    }
                    .font(.halsynCaption)
                }
            }
        }
    }
}
