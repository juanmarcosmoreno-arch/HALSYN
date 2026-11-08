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
                    NavigationLink {
                        NightDetailView(night: night, targetHours: sleepTarget)
                    } label: {
                        LastNightCard(night: night, targetHours: sleepTarget)
                    }
                    .buttonStyle(.plain)
                } else {
                    HalsynCard {
                        HalsynEmptyState(systemImage: "moon.zzz", title: "Sin sueño registrado", message: "Lleva el Apple Watch al dormir (o usa otra app que guarde el sueño en Salud) para ver tus noches aquí.")
                    }
                }
                if !data.nights.isEmpty {
                    let recentNights = Array(data.nights.suffix(14))
                    SleepScheduleCard(nights: recentNights, targetHours: $sleepTarget)
                    SleepRegularityCard(nights: recentNights)
                    SleepPatternCard(pattern: SleepPattern.analyze(data.nights, calendar: .current))
                }
                NavigationLink {
                    MetricDetailView(kind: .heartRateVariability)
                } label: {
                    BaselineTrendCard(
                        title: "Variabilidad cardíaca (HRV)",
                        eyebrow: HalsynLexicon.puls.rawValue,
                        series: data.hrv,
                        unit: "ms",
                        explanation: "Más alta que tu rango habitual suele acompañar a un buen descanso; más baja, a cansancio, estrés o enfermedad. Compárala solo contigo."
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MetricDetailView(kind: .restingHeartRate)
                } label: {
                    BaselineTrendCard(
                        title: "FC en reposo",
                        eyebrow: HalsynLexicon.puls.rawValue,
                        series: data.restingHeartRate,
                        unit: "lpm",
                        explanation: "Una FC en reposo por encima de tu rango habitual durante varios días puede indicar que necesitas más descanso."
                    )
                }
                .buttonStyle(.plain)
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
            async let nights = provider.sleepNights(endingOn: today, days: 28)
            async let hrv = provider.dailySeries(.heartRateVariability, days: 56, endingOn: today)
            async let rhr = provider.dailySeries(.restingHeartRate, days: 56, endingOn: today)
            data = VilaData(recovery: await recovery, nights: await nights, hrv: await hrv, restingHeartRate: await rhr)
        }
    }
}

// MARK: - Recuperación

struct RecoveryCard: View {
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
                        if let title = estimate?.band?.title {
                            Text(LocalizedStringKey(title))
                                .font(.halsynHeadline)
                                .foregroundStyle(.halsynPrimaryText)
                        }
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
                    NavigationLink {
                        RecoveryExplanationView(estimate: estimate)
                    } label: {
                        Label("¿Por qué tengo este puntaje?", systemImage: "questionmark.circle")
                            .font(.halsynCaption.weight(.semibold))
                    }
                }

                let values = history.compactMap { estimate in estimate.value.map { DailyValue(day: estimate.day, value: Double($0)) } }
                if values.count >= 3 {
                    Divider().overlay(Color.halsynHairline)
                    Text("Últimas 4 semanas")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    HalsynTrendChart(values: values, title: "Recuperación", yDomain: 0...100, usualRange: usualRange(values.map(\.value)), events: HealthEventStore.shared.spans(from: values.first?.day ?? .now, to: values.last?.day ?? .now))
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

struct LastNightCard: View {
    let night: SleepNight
    let targetHours: Double
    /// Título de la tarjeta; `nil` = "Anoche".
    var title: String?

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    HalsynSectionHeader(title ?? String(localized: "Anoche"), eyebrow: HalsynLexicon.somn.rawValue)
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

struct SleepScheduleCard: View {
    let nights: [SleepNight]
    @Binding var targetHours: Double

    var body: some View {
        let regularity = SleepRegularity(nights, calendar: .current)
        let lastWeek = Array(nights.suffix(7))
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tus noches · 14 días", eyebrow: HalsynLexicon.tid.rawValue)
                HalsynSleepScheduleChart(nights: nights, targetHours: targetHours)
                NavigationLink {
                    SleepNightsView()
                } label: {
                    DetailLinkRow("Ver todas las noches", systemImage: "moon.zzz")
                }
                .buttonStyle(.plain)

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

struct BaselineTrendCard: View {
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
                HalsynTrendChart(values: shown, title: series.kind.shortTitle, usualRange: usualRange(reference), unit: unit, events: HealthEventStore.shared.spans(from: shown.first?.day ?? .now, to: shown.last?.day ?? .now))
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

// MARK: - ¿Por qué tengo este puntaje?

/// Explicación de la recuperación de un día: variables, valores recientes y
/// basales, qué sube o baja el resultado, qué falta y con qué confianza.
struct RecoveryExplanationView: View {
    let estimate: RecoveryEstimate

    var body: some View {
        Form {
            Section {
                LabeledContent("Recuperación estimada", value: estimate.value.map(String.init) ?? "—")
                LabeledContent("Confianza", value: confidence)
                LabeledContent("Datos disponibles", value: "\(Int((estimate.coverage * 100).rounded())) %")
            } footer: {
                Text("Primero la media de los componentes con dato, cada uno con su peso: HRV 35 %, FC en reposo 25 %, sueño 25 % y esfuerzo reciente 15 %. En tu línea basal un componente vale 75; mejor que lo habitual sube hasta 100 y peor baja hasta 15. Si falta un componente, se reparte su peso entre los demás (con al menos el 60 % del peso y una señal del corazón). Después, para que una señal mala no quede tapada por las buenas: 75 % la media y 25 % el componente más bajo. Con una enfermedad, fiebre o lesión registradas, como mucho 50.")
            }
            Section("Resumen") {
                ForEach(RecoveryExplanationText.lines(estimate), id: \.self) { line in
                    Text(verbatim: line)
                        .font(.halsynCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !estimate.warnings.isEmpty {
                Section("Avisos") {
                    ForEach(estimate.warnings, id: \.self) { warning in
                        Label(RecoveryExplanationText.warning(warning), systemImage: "exclamationmark.triangle")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynCaution)
                    }
                }
            }
            Section("Variables") {
                ForEach(estimate.components) { component in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(LocalizedStringKey(component.kind.title), systemImage: component.kind.systemImage)
                                .font(.halsynCaption.weight(.semibold))
                            Spacer()
                            Text(verbatim: component.score.map(String.init) ?? "—")
                                .font(.halsynCaption.monospacedDigit().weight(.semibold))
                        }
                        Text(verbatim: String(localized: "Peso") + " \(Int((component.weight * 100).rounded())) %" + RecoveryExplanationText.contribution(component, in: estimate))
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                        if let line = RecoveryExplanationText.values(component) {
                            Text(verbatim: line)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        Text(RecoveryExplanationText.effect(component))
                            .font(.caption2)
                            .foregroundStyle(component.impact == .negative ? Color.halsynCaution : Color.halsynSecondaryText)
                        if let note = RecoveryExplanationText.isolatedDrop(component) {
                            Text(verbatim: note)
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            let missing = estimate.components.filter { $0.score == nil }
            if !missing.isEmpty {
                Section("Datos que faltan") {
                    ForEach(missing) { component in
                        Text(verbatim: String(localized: String.LocalizationValue(component.kind.title)) + ": " + (component.missingReason == .insufficientHistory ? String(localized: "faltan días para conocer tu media") : String(localized: "sin datos")))
                            .font(.halsynCaption)
                    }
                }
            }
            Section {
                Text("Estimación orientativa del equilibrio entre esfuerzo y descanso, comparada solo contigo. No es una medida clínica validada ni un diagnóstico, y no dice si estás médicamente recuperado.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                Text(verbatim: "RecoveryEngine \(estimate.engineVersion)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("¿Por qué este puntaje?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var confidence: String {
        switch estimate.confidence {
        case .high: String(localized: "Alta")
        case .medium: String(localized: "Media")
        case .low: String(localized: "Baja")
        }
    }
}

enum RecoveryExplanationText {
    /// Resumen, factores a favor y en contra, agregación, calidad y confianza.
    static func lines(_ estimate: RecoveryEstimate) -> [String] {
        guard let value = estimate.value else {
            return [String(localized: "Sin estimación: hacen falta tu HRV o tu FC en reposo y unos días de historial.")]
        }
        var lines: [String] = []
        let scored = estimate.components.filter { $0.score != nil }
        let up = scored.filter { $0.impact == .positive }.map { String(localized: String.LocalizationValue($0.kind.title)) }
        let down = scored.filter { $0.impact == .negative }.map { String(localized: String.LocalizationValue($0.kind.title)) }
        let valueText = String(value)
        if down.isEmpty && up.isEmpty {
            lines.append(String(localized: "Recuperación \(valueText): todo cerca de tu línea basal."))
        } else if down.isEmpty {
            lines.append(String(localized: "Recuperación \(valueText): mejor que tu línea basal, sin señales en contra."))
        } else {
            let downText = down.joined(separator: ", ")
            lines.append(String(localized: "Recuperación \(valueText): la baja sobre todo \(downText)."))
        }
        let upText = up.joined(separator: ", "), againstText = down.joined(separator: ", ")
        if !up.isEmpty { lines.append(String(localized: "A favor: \(upText)")) }
        if !down.isEmpty { lines.append(String(localized: "En contra: \(againstText)")) }
        if let mean = estimate.weightedMean, let lowest = scored.compactMap(\.score).min() {
            let meanText = HalsynFormat.decimal(mean, fractionDigits: 1), lowestText = String(lowest)
            lines.append(String(localized: "Cálculo: 75 % de la media ponderada (\(meanText)) + 25 % del componente más bajo (\(lowestText)) = \(valueText). Así una señal mala no queda compensada del todo por las buenas."))
        }
        let coverageText = "\(Int((estimate.coverage * 100).rounded())) %"  // nolocalize
        let confidenceText: String
        switch estimate.confidence {
        case .high: confidenceText = String(localized: "alta")
        case .medium: confidenceText = String(localized: "media")
        case .low: confidenceText = String(localized: "baja")
        }
        lines.append(String(localized: "Comparado solo contigo (tu línea basal de 28 días). Datos disponibles: \(coverageText) del peso; confianza \(confidenceText)."))
        for item in estimate.warnings { lines.append(Self.warning(item)) }
        return lines
    }

    static func warning(_ warning: RecoveryWarning) -> String {
        switch warning {
        case .hrvUnusuallyHigh:
            return String(localized: "HRV muy por encima de lo habitual. Puede ser buena señal, pero a veces acompaña a cansancio acumulado: por eso no suma más que un valor algo alto.")
        case .illness:
            return String(localized: "Registraste enfermedad, fiebre o lesión: la recuperación se limita a 50, aunque las señales parezcan buenas.")
        case let .recentHardSession(hours):
            let hoursText = String(hours)
            return String(localized: "Sesión intensa hace unas \(hoursText) h: el cuerpo puede seguir recuperándose aunque las señales de la mañana sean buenas.")
        case .incompleteSleep:
            return String(localized: "La noche parece incompleta (registro muy corto): el sueño no entra en el cálculo.")
        case .shortHRVWindow:
            return String(localized: "Menos de 4 días con HRV en la última semana: la media es menos fiable.")
        case .usesYesterday:
            return String(localized: "Algún valor es de ayer: todavía no hay medición de hoy.")
        }
    }

    /// Aporte en puntos frente a la base de 75: peso relativo × (puntos − 75).
    static func contribution(_ component: RecoveryComponent, in estimate: RecoveryEstimate) -> String {
        guard let score = component.score, estimate.value != nil else { return "" }
        let total = estimate.components.filter { $0.score != nil }.map(\.weight).reduce(0, +)
        guard total > 0 else { return "" }
        let points = component.weight / total * Double(score - 75)
        let text = (points >= 0 ? "+" : "−") + HalsynFormat.decimal(abs(points), fractionDigits: 1)
        return " · " + String(localized: "aporte \(text) puntos frente a la base de 75")
    }

    static func values(_ component: RecoveryComponent) -> String? {
        guard let recent = component.recentValue else { return nil }
        let daysText = String(component.baselineDays)
        switch component.kind {
        case .heartRateVariability:
            let value = HalsynFormat.decimal(recent, fractionDigits: 1)
            let base = component.baselineValue.map { HalsynFormat.decimal($0, fractionDigits: 1) } ?? "—"
            let windowText = String(component.windowDays)
            var line = String(localized: "Media de 7 días (\(windowText) con dato): \(value) ms · tu línea basal: \(base) ms (mediana de \(daysText) días)")
            if let trend = component.weeklyTrend {
                let trendText = (trend >= 0 ? "+" : "−") + HalsynFormat.integer(abs(trend * 100)) + " %"
                line += " · " + String(localized: "frente a la semana anterior: \(trendText)")
            }
            return line
        case .restingHeartRate:
            let value = HalsynFormat.integer(recent)
            let base = component.baselineValue.map { HalsynFormat.integer($0) } ?? "—"
            return String(localized: "Hoy: \(value) lpm · tu línea basal: \(base) lpm (mediana de \(daysText) días)")
        case .sleep:
            let value = HalsynFormat.decimal(recent, fractionDigits: 1)
            let base = component.baselineValue.map { HalsynFormat.decimal($0, fractionDigits: 1) } ?? "—"
            var line = String(localized: "Anoche: \(value) h · tu sueño habitual: \(base) h (recomendado 7–9 h)")
            if let nap = component.napHours {
                let napText = HalsynFormat.decimal(nap, fractionDigits: 1)
                line += " · " + String(localized: "siesta de \(napText) h aparte")
            }
            return line
        case .recentLoad:
            let value = HalsynFormat.integer(recent)
            let base = component.baselineValue.map { HalsynFormat.integer($0) } ?? "—"
            return String(localized: "Últimos 3 días: \(value) min de ejercicio al día · tu media: \(base) min")
        }
    }

    static func effect(_ component: RecoveryComponent) -> LocalizedStringKey {
        if component.possiblyIncomplete { return "No entra en el cálculo: el registro de anoche es muy corto frente a lo habitual y parece incompleto (por ejemplo, el reloj sin batería)." }
        if component.score == nil { return "No entra en el cálculo." }
        switch component.impact {
        case .positive: return "Sube el resultado: mejor que tu línea basal."
        case .negative: return "Baja el resultado: peor que tu línea basal."
        case .neutral: return "Neutral: cerca de tu línea basal."
        }
    }

    /// Una caída de la HRV de un solo día que el promedio de 3 días suaviza.
    static func isolatedDrop(_ component: RecoveryComponent) -> String? {
        guard component.kind == .heartRateVariability, let day = component.singleDayValue, let mean = component.recentValue,
              mean > 0, day < 0.85 * mean else { return nil }
        let dayText = HalsynFormat.decimal(day, fractionDigits: 1)
        return String(localized: "Hoy la HRV fue \(dayText) ms, más baja que la media de la semana. Una sola medición varía mucho (sueño, alcohol, hora de la medición): por eso se usa la media de 7 días en escala logarítmica (Plews et al.) y una caída aislada pesa poco. Si sigue baja varios días, el puntaje bajará.")
    }
}

// MARK: - Patrón de sueño

/// Duración, regularidad y tendencia de 4 semanas, con noches a revisar.
struct SleepPatternCard: View {
    let pattern: SleepPattern

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Patrón de sueño", eyebrow: HalsynLexicon.somn.rawValue)
                LabeledContent("Media de 7 noches", value: hours(pattern.average7))
                    .font(.halsynCaption)
                LabeledContent("Media de 28 noches", value: hours(pattern.average28))
                    .font(.halsynCaption)
                if let variation = pattern.midpointVariation {
                    LabeledContent("Variación del horario", value: "± \(HalsynFormat.integer(variation)) min")
                        .font(.halsynCaption)
                }
                if let trend = pattern.trendPerWeek {
                    LabeledContent("Tendencia", value: (trend >= 0 ? "+" : "−") + "\(HalsynFormat.integer(abs(trend) * 60)) min / " + String(localized: "semana"))
                        .font(.halsynCaption)
                }
                if pattern.repeatedShortSleep {
                    let count = pattern.shortNightsLast7
                    Label("Esta semana dormiste menos de 6 h en \(count) noches. Varias noches cortas seguidas suelen acompañar a una recuperación más baja; si se repite, conviene priorizar el descanso.", systemImage: "moon.zzz")
                        .font(.caption2)
                        .foregroundStyle(.halsynCaution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !pattern.flaggedNights.isEmpty || !pattern.unusualTimingDays.isEmpty {
                    Text("Registros a revisar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                    ForEach(Array(pattern.flaggedNights.suffix(6).enumerated()), id: \.offset) { _, item in
                        Text(verbatim: item.day.formatted(.dateTime.day().month(.abbreviated)) + ": " + item.flags.map(SleepFlagText.text).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    if !pattern.unusualTimingDays.isEmpty {
                        let daysText = pattern.unusualTimingDays.suffix(6).map { $0.formatted(.dateTime.day().month(.abbreviated)) }.joined(separator: ", ")
                        Text("Horario muy distinto del habitual: \(daysText)")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
                ExpandableText("La duración incluye las siestas, pero el horario de la noche usa solo el sueño principal (tramos separados por 90 min o más cuentan aparte). Las fases (profundo, REM) que estima el reloj no son una medición clínica: aquí no se usan para sacar conclusiones.")
            }
        }
    }

    private func hours(_ value: Double?) -> String {
        value.map { sleepText($0 * 3600) } ?? "—"
    }
}

enum SleepFlagText {
    static func text(_ flag: SleepNightFlag) -> String {
        switch flag {
        case .napIncluded: String(localized: "siesta sumada al total")
        case .multipleSources: String(localized: "varias fuentes (fusionadas)")
        case .shortRecord: String(localized: "registro corto: quizá incompleto")
        case .fragmented: String(localized: "sueño fragmentado")
        }
    }
}
