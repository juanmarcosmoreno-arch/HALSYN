import HalsynCore
import HalsynDesign
import SwiftUI

/// VILA — descanso: recuperación estimada, la última noche, horarios y
/// regularidad del sueño, y tendencias de HRV y FC en reposo frente a tu rango habitual.
struct VilaView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.sleepTargetKey) private var sleepTarget: Double = SleepTarget.defaultHours
    @State private var data: VilaData?

    struct VilaData {
        var recovery: [RecoveryEstimate]
        var nights: [SleepNight]
        var hrv: MetricSeries
        var restingHeartRate: MetricSeries
    }

    var body: some View {
        HalsynScreen {
            ModuleHeader(module: .vila, isDemo: model.isDemo)
                .padding(.top, HalsynSpacing.s)

            if let data {
                RecoveryCard(estimate: data.recovery.last, history: data.recovery)
                if let night = data.nights.last {
                    LastNightCard(night: night, targetHours: sleepTarget)
                } else {
                    HalsynCard {
                        HalsynEmptyState(systemImage: "moon.zzz", title: "Sin sueño registrado", message: "Lleva el Apple Watch al dormir (o usa otra app que guarde el sueño en Salud) para ver tus noches aquí.")
                    }
                }
                if !data.nights.isEmpty {
                    SleepScheduleCard(nights: data.nights, targetHours: $sleepTarget)
                }
                BaselineTrendCard(
                    title: "Variabilidad cardíaca (HRV)",
                    eyebrow: HalsynLexicon.puls.rawValue,
                    series: data.hrv,
                    unit: "ms",
                    explanation: "Más alta que tu rango habitual suele acompañar a un buen descanso; más baja, a cansancio, estrés o enfermedad. Compárala solo contigo."
                )
                BaselineTrendCard(
                    title: "FC en reposo",
                    eyebrow: HalsynLexicon.puls.rawValue,
                    series: data.restingHeartRate,
                    unit: "lpm",
                    explanation: "Una FC en reposo por encima de tu rango habitual durante varios días puede indicar que necesitas más descanso."
                )
                if !model.isDemo {
                    HealthAccessHint()
                }
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.vila.brandName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.reloadKey) {
            let today = Date.now
            let provider = model.provider
            async let recovery = provider.recoveryEstimates(endingOn: today, days: 28)
            async let nights = provider.sleepNights(endingOn: today, days: 14)
            async let hrv = provider.dailySeries(.heartRateVariability, days: 56, endingOn: today)
            async let rhr = provider.dailySeries(.restingHeartRate, days: 56, endingOn: today)
            data = VilaData(recovery: await recovery, nights: await nights, hrv: await hrv, restingHeartRate: await rhr)
        }
    }
}

// MARK: - Recuperación

private struct RecoveryCard: View {
    let estimate: RecoveryEstimate?
    let history: [RecoveryEstimate]

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Recuperación estimada", eyebrow: HalsynModule.vila.brandName)
                HStack(alignment: .center, spacing: HalsynSpacing.l) {
                    HalsynScoreRing(score: estimate?.value, caption: estimate?.band?.title)
                        .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                        if let estimate, estimate.value != nil {
                            Label(confidenceText(estimate.confidence), systemImage: "gauge.with.dots.needle.33percent")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        } else {
                            Text("Hacen falta tu HRV o tu FC en reposo y unos días de historial para estimarla.")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                }

                if let estimate {
                    VStack(spacing: HalsynSpacing.s) {
                        ForEach(estimate.components) { component in
                            RecoveryComponentRow(component: component)
                        }
                    }
                }

                let values = history.compactMap { estimate in estimate.value.map { DailyValue(day: estimate.day, value: Double($0)) } }
                if values.count >= 3 {
                    Divider().overlay(Color.halsynHairline)
                    Text("Últimas 4 semanas")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    HalsynTrendChart(values: values, title: "Recuperación", yDomain: 0...100, usualRange: usualRange(values.map(\.value)))
                        .frame(height: 200)
                }

                Text("Estimación orientativa del equilibrio entre esfuerzo y descanso. No indica si estás médicamente recuperado.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                DataOriginFootnote(origin: estimate?.origin, extra: "RecoveryEngine \(RecoveryEngine.version)")
            }
        }
    }

    private func confidenceText(_ confidence: ScoreConfidence) -> LocalizedStringKey {
        switch confidence {
        case .high: "Confianza alta"
        case .medium: "Confianza media"
        case .low: "Confianza baja: faltan datos"
        }
    }
}

/// Rango habitual: media ± 1 desviación típica (al menos 7 valores).
func usualRange(_ values: [Double]) -> ClosedRange<Double>? {
    guard values.count >= 7 else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    let deviation = variance.squareRoot()
    return (mean - deviation)...(mean + deviation)
}

private struct RecoveryComponentRow: View {
    let component: RecoveryComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: HalsynSpacing.s) {
                Image(systemName: component.kind.systemImage)
                    .foregroundStyle(.halsynAccentText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(component.kind.title))
                    .font(.halsynCaption.weight(.semibold))
                    .foregroundStyle(.halsynPrimaryText)
                Spacer()
                Text(verbatim: component.score.map(String.init) ?? "—")
                    .font(.halsynCaption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.halsynPrimaryText)
            }
            // Barra de 0 a 100 con la marca de "en tu media" (75).
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.halsynHairline)
                    if let score = component.score {
                        Capsule()
                            .fill(Color.halsynChart.opacity(component.impact == .negative ? 0.5 : 1))
                            .frame(width: max(6, proxy.size.width * CGFloat(score) / 100))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
            if component.usesPreviousDay {
                Text("Valor de ayer: aún no hay medición de hoy")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: LocalizedStringKey {
        if let reason = component.missingReason {
            return reason == .insufficientHistory ? "Faltan días para conocer tu media" : "Sin datos"
        }
        guard let value = component.detail else { return "" }
        let text: LocalizedStringKey
        switch component.kind {
        case .heartRateVariability:
            let percent = "\(HalsynFormat.integer(abs(value * 100))) %"
            text = value >= 0 ? "\(percent) por encima de tu media" : "\(percent) por debajo de tu media"
        case .restingHeartRate:
            let bpm = HalsynFormat.integer(abs(value))
            text = abs(value) < 1 ? "En tu media" : (value > 0 ? "\(bpm) lpm por encima de tu media" : "\(bpm) lpm por debajo de tu media")
        case .sleep:
            text = "\(sleepText(value * 3600)) dormidas"
        case .recentLoad:
            text = value <= 1 ? "Esfuerzo similar o menor que lo habitual" : "\(HalsynFormat.decimal(value, fractionDigits: 1)) veces tu esfuerzo habitual"
        }
        return text
    }
}

// MARK: - Última noche

private struct LastNightCard: View {
    let night: SleepNight
    let targetHours: Double

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    HalsynSectionHeader("Anoche", eyebrow: HalsynLexicon.somn.rawValue)
                    if night.origin.isDemo { HalsynDemoBadge() }
                }
                HStack(alignment: .firstTextBaseline, spacing: HalsynSpacing.l) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: sleepText(night.asleep))
                            .font(.system(size: 34, weight: .light, design: .rounded))
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: "\(night.sleepStart.formatted(date: .omitted, time: .shortened)) → \(night.sleepEnd.formatted(date: .omitted, time: .shortened))")
                            .font(.halsynCaption.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let efficiency = night.efficiency {
                            Text(verbatim: "\(Int((efficiency * 100).rounded())) %")
                                .font(.halsynHeadline)
                                .foregroundStyle(.halsynPrimaryText)
                            Text("Tiempo dormido")
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                }
                targetBar

                if night.hasStages {
                    HalsynSleepComposition(night: night)
                    if !night.segments.isEmpty {
                        HalsynHypnogram(night: night)
                    }
                } else {
                    Label("Esta fuente no registra fases del sueño.", systemImage: "info.circle")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
                DataOriginFootnote(origin: night.origin, extra: "«Tiempo dormido» es la parte del periodo entre dormirte y despertarte que pasaste dormido.")
            }
        }
    }

    /// Progreso hacia el objetivo de sueño.
    private var targetBar: some View {
        let fraction = min(night.asleep / (targetHours * 3600), 1)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.halsynHairline)
                    Capsule().fill(Color.halsynChart).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text("Objetivo: \(sleepText(targetHours * 3600))")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Horarios y regularidad

private struct SleepScheduleCard: View {
    let nights: [SleepNight]
    @Binding var targetHours: Double

    var body: some View {
        let regularity = SleepRegularity(nights, calendar: .current)
        let lastWeek = Array(nights.suffix(7))
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tus noches · 14 días", eyebrow: HalsynLexicon.tid.rawValue)
                HalsynSleepScheduleChart(nights: nights, targetHours: targetHours)

                if let regularity {
                    HStack(alignment: .top) {
                        stat(title: "Te dormiste", value: clock(regularity.averageSleepStart), detail: variation(regularity.sleepStartVariation))
                        Spacer()
                        stat(title: "Te despertaste", value: clock(regularity.averageSleepEnd), detail: variation(regularity.sleepEndVariation))
                    }
                    Text("Media y variación de los horarios. Horarios estables suelen ayudar a dormir mejor.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }

                Divider().overlay(Color.halsynHairline)

                HalsynTrendChart(
                    values: nights.map { DailyValue(day: $0.day, value: $0.asleep / 3600) },
                    title: "Sueño",
                    style: .bar,
                    target: targetHours,
                    format: { sleepText($0 * 3600) }
                )
                .frame(height: 220)

                let shortfall = SleepTarget.shortfall(lastWeek, targetHours: targetHours)
                Label(shortfall > 0 ? LocalizedStringKey("Esta semana te faltaron \(sleepText(shortfall)) respecto a tu objetivo.") : LocalizedStringKey("Esta semana alcanzaste tu objetivo todas las noches registradas."), systemImage: "moon.stars")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)

                Stepper(value: $targetHours, in: SleepTarget.range, step: 0.25) {
                    LabeledContent("Objetivo de sueño", value: sleepText(targetHours * 3600))
                        .font(.halsynCaption)
                }
                Text("La recomendación general para adultos es de 7 a 9 horas.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private func stat(title: LocalizedStringKey, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.halsynSecondaryText)
            Text(verbatim: value).font(.halsynHeadline.monospacedDigit()).foregroundStyle(.halsynPrimaryText)
            Text(verbatim: detail).font(.caption2.monospacedDigit()).foregroundStyle(.halsynSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func clock(_ minutes: Double) -> String {
        let time = SleepRegularity.clockTime(minutesFromNoon: minutes)
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        return (Calendar.current.date(from: components) ?? .now).formatted(date: .omitted, time: .shortened)
    }

    private func variation(_ minutes: Double) -> String {
        "± \(Int(minutes.rounded())) min"
    }
}

// MARK: - HRV y FC en reposo

private struct BaselineTrendCard: View {
    let title: LocalizedStringKey
    let eyebrow: String
    let series: MetricSeries
    let unit: String
    let explanation: LocalizedStringKey

    var body: some View {
        // Se muestran los últimos 28 días; el rango habitual sale de los 28 anteriores.
        let cutoff = Calendar.current.date(byAdding: .day, value: -27, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let shown = series.values.filter { $0.day >= cutoff }
        let reference = series.values.filter { $0.day < cutoff }.map(\.value)
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                Text(verbatim: eyebrow).halsynEyebrowStyle()
                Text(title)
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                HalsynTrendChart(values: shown, title: series.kind.shortTitle, usualRange: usualRange(reference), unit: unit)
                    .frame(height: 220)
                Text(explanation)
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                DataOriginFootnote(origin: series.origin)
            }
        }
    }
}

#Preview {
    NavigationStack { VilaView() }
        .environment(AppModel())
}
