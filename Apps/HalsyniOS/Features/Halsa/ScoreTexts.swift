import HalsynCore
import HalsynDesign
import SwiftUI

/// Textos localizados de la puntuación y del resumen del día. Los motores
/// devuelven datos estructurados; aquí se convierten en frases traducibles.
enum ScoreTexts {
    static func hoursAndMinutes(_ hours: Double) -> String {
        let time = HalsynFormat.hoursAndMinutes(hours)
        return String(localized: "\(time.hours) h \(time.minutes) min")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func factor(_ factor: ScoreFactor) -> Text {
        switch factor.kind {
        case .sleepDuration(let hours):
            let time = hoursAndMinutes(hours)
            return Text("Sueño de \(time) (recomendado: 7–9 h)")
        case .restingHeartRate(let delta):
            if factor.impact == .negative {
                let value = HalsynFormat.integer(delta)
                return Text("FC en reposo \(value) lpm por encima de tu media")
            }
            return Text("FC en reposo dentro de tu rango habitual")
        case .heartRateVariability(let relative):
            if factor.impact == .negative {
                let value = percent(-relative)
                return Text("HRV un \(value) por debajo de tu media")
            }
            return Text("HRV dentro o por encima de tu rango habitual")
        case .averageSteps(let perDay):
            let value = HalsynFormat.integer(perDay)
            return Text("Media de \(value) pasos al día en los últimos 7 días")
        case .weeklyExercise(let minutes):
            let value = HalsynFormat.integer(minutes)
            return Text("\(value) min de ejercicio en los últimos 7 días (referencia: 150)")
        case .trainingLoadRatio(let ratio):
            switch factor.impact {
            case .negative:
                let value = HalsynFormat.decimal(ratio, fractionDigits: 1)
                return Text("Carga reciente alta frente a tu habitual (\(value)×)")
            case .neutral:
                return Text("Carga reciente más baja que tu habitual")
            case .positive:
                return Text("Carga reciente acorde a tu habitual")
            }
        }
    }

    static func statement(_ statement: SummaryStatement) -> Text {
        switch statement {
        case .overall(let band):
            switch band {
            case .low: return Text("Hoy ha sido un día para cuidarte.")
            case .fair: return Text("Hoy tu equilibrio general ha sido moderado.")
            case .good: return Text("Hoy has tenido un buen equilibrio general.")
            case .excellent: return Text("Hoy has tenido un equilibrio general excelente.")
            }
        case .activity(let relation):
            switch relation {
            case .above: return Text("Tu actividad de hoy ha estado por encima de tu promedio.")
            case .within: return Text("Tu actividad de hoy ha estado dentro de tu promedio.")
            case .below: return Text("Tu actividad de hoy ha estado por debajo de tu promedio.")
            }
        case .restingHeartRate(let relation):
            switch relation {
            case .above: return Text("Tu frecuencia cardíaca en reposo ha estado por encima de tu rango habitual.")
            case .within: return Text("Tu frecuencia cardíaca en reposo se ha mantenido dentro de tu rango habitual.")
            case .below: return Text("Tu frecuencia cardíaca en reposo ha estado por debajo de tu rango habitual.")
            }
        case .sleep(let hours, let within):
            let time = hoursAndMinutes(hours)
            return within
                ? Text("Anoche dormiste \(time), dentro de lo recomendado.")
                : Text("Anoche dormiste \(time), fuera del rango recomendado de 7–9 h.")
        case .weeklyExercise(let minutes, let meets):
            let value = HalsynFormat.integer(minutes)
            return meets
                ? Text("Llevas \(value) min de ejercicio en los últimos 7 días: alcanzas la referencia de 150.")
                : Text("Llevas \(value) min de ejercicio en los últimos 7 días (referencia: 150).")
        }
    }

    static func statementIcon(_ statement: SummaryStatement) -> String {
        switch statement {
        case .overall: "sparkles"
        case .activity: "shoeprints.fill"
        case .restingHeartRate: "heart"
        case .sleep: "moon"
        case .weeklyExercise: "figure.run"
        }
    }

    static func missing(_ reason: DimensionScore.MissingReason) -> LocalizedStringKey {
        switch reason {
        case .noData: "Sin datos"
        case .insufficientHistory: "Necesita más días de historial"
        }
    }

    static func confidence(_ confidence: ScoreConfidence) -> LocalizedStringKey {
        switch confidence {
        case .high: "Confianza alta"
        case .medium: "Confianza media"
        case .low: "Confianza baja"
        }
    }

    static func level(_ impact: ScoreImpact) -> HalsynStatusIndicator.Level {
        switch impact {
        case .positive: .positive
        case .neutral: .neutral
        case .negative: .caution
        }
    }

    static func icon(_ impact: ScoreImpact) -> String {
        switch impact {
        case .positive: "checkmark.circle.fill"
        case .neutral: "circle.dotted"
        case .negative: "exclamationmark.triangle.fill"
        }
    }

    static func color(_ impact: ScoreImpact) -> Color {
        switch impact {
        case .positive: .halsynPositive
        case .neutral: .halsynSecondaryText
        case .negative: .halsynCaution
        }
    }
}

/// Fila de factor: icono de impacto + frase (nunca solo color).
struct ScoreFactorRow: View {
    let factor: ScoreFactor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HalsynSpacing.s) {
            Image(systemName: ScoreTexts.icon(factor.impact))
                .foregroundStyle(ScoreTexts.color(factor.impact))
                .accessibilityHidden(true)
            ScoreTexts.factor(factor)
                .font(.halsynCaption)
                .foregroundStyle(.halsynPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
