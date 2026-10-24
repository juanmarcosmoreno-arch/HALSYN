import HalsynCore
import HalsynDesign
import SwiftUI

/// Fila "Ver más ›" dentro de una tarjeta.
struct DetailLinkRow: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .font(.halsynCaption.weight(.semibold))
                .foregroundStyle(.halsynAccentText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.halsynSecondaryText)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Todas las noches

/// SÖMN: las últimas 30 noches, medias del mes y acceso a cada noche.
struct SleepNightsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.sleepTargetKey) private var sleepTarget: Double = SleepTarget.defaultHours
    @State private var nights: [SleepNight]?

    var body: some View {
        HalsynScreen {
            if let nights {
                if nights.isEmpty {
                    HalsynCard {
                        HalsynEmptyState(systemImage: "moon.zzz", title: "Sin sueño registrado", message: "Lleva el Apple Watch al dormir (o usa otra app que guarde el sueño en Salud) para ver tus noches aquí.")
                    }
                } else {
                    averagesCard(nights)
                    SleepRegularityCard(nights: nights)
                    HalsynCard {
                        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                            HalsynSectionHeader("Horarios · 30 días", eyebrow: HalsynLexicon.tid.rawValue)
                            HalsynSleepScheduleChart(nights: nights, targetHours: sleepTarget)
                        }
                    }
                    HalsynSectionHeader("Noche a noche", eyebrow: HalsynLexicon.somn.rawValue)
                        .padding(.top, HalsynSpacing.s)
                    ForEach(nights.reversed()) { night in
                        NavigationLink {
                            NightDetailView(night: night, targetHours: sleepTarget)
                        } label: {
                            NightRow(night: night, targetHours: sleepTarget)
                        }
                        .buttonStyle(.plain)
                    }
                    DataOriginFootnote(origin: nights.last?.origin)
                }
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle(Text("Sueño"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.reloadKey) {
            nights = await model.provider.sleepNights(endingOn: .now, days: 30)
        }
    }

    private func averagesCard(_ nights: [SleepNight]) -> some View {
        let count = Double(nights.count)
        let asleep = nights.map(\.asleep).reduce(0, +) / count
        let efficiencies = nights.compactMap(\.efficiency)
        let staged = nights.filter(\.hasStages)
        let reachedTarget = nights.filter { $0.asleep >= sleepTarget * 3600 }.count
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Tu media · 30 días", eyebrow: HalsynLexicon.somn.rawValue)
                HStack(alignment: .top) {
                    HalsynMetric(title: "Dormido", value: sleepText(asleep), unit: "")
                    Spacer()
                    if !efficiencies.isEmpty {
                        let efficiency = efficiencies.reduce(0, +) / Double(efficiencies.count)
                        HalsynMetric(title: "Tiempo dormido", value: HalsynFormat.integer(efficiency * 100), unit: "%")
                    }
                }
                Text("Llegaste a tu objetivo en \(reachedTarget) de \(nights.count) noches.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                if !staged.isEmpty {
                    Divider().overlay(Color.halsynHairline)
                    Text("Fases por noche, de media")
                        .font(.halsynCaption.weight(.semibold))
                        .foregroundStyle(.halsynPrimaryText)
                    ForEach([SleepSample.Stage.asleepDeep, .asleepCore, .asleepREM, .awake], id: \.self) { stage in
                        let average = staged.map { $0.stages[stage] ?? 0 }.reduce(0, +) / Double(staged.count)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(stage.color).frame(width: 10, height: 10)
                            Text(LocalizedStringKey(stage.title))
                                .foregroundStyle(.halsynPrimaryText)
                            Spacer()
                            Text(verbatim: sleepText(average))
                                .monospacedDigit()
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Una noche en la lista: fecha, horas, horario y barra de fases.
private struct NightRow: View {
    let night: SleepNight
    let targetHours: Double

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(night.day, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                        .font(.halsynCaption.weight(.semibold))
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    Text(verbatim: sleepText(night.asleep))
                        .font(.halsynHeadline.monospacedDigit())
                        .foregroundStyle(night.asleep >= targetHours * 3600 ? Color.halsynAccentText : Color.halsynPrimaryText)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                        .accessibilityHidden(true)
                }
                Text(verbatim: "\(night.sleepStart.formatted(date: .omitted, time: .shortened)) → \(night.sleepEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
                if night.hasStages {
                    StageBar(night: night)
                }
            }
        }
    }
}

/// Barra fina con la proporción de cada fase.
private struct StageBar: View {
    let night: SleepNight

    var body: some View {
        let parts = SleepSample.Stage.hypnogramOrder.compactMap { stage -> (stage: SleepSample.Stage, seconds: TimeInterval)? in
            let seconds = night.stages[stage] ?? 0
            return seconds > 0 ? (stage, seconds) : nil
        }
        let total = max(parts.reduce(0) { $0 + $1.seconds }, 1)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(parts, id: \.stage) { part in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(part.stage.color)
                        .frame(width: max(3, (proxy.size.width - CGFloat(max(parts.count - 1, 0)) * 2) * part.seconds / total))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Una noche

/// Detalle de una noche: duración, horario, fases e hipnograma, y su
/// comparación con tu media de las 4 semanas anteriores.
struct NightDetailView: View {
    let night: SleepNight
    let targetHours: Double

    @Environment(AppModel.self) private var model
    @State private var previous: [SleepNight]?

    var body: some View {
        HalsynScreen {
            LastNightCard(night: night, targetHours: targetHours, title: night.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            if let previous, previous.count >= 7 {
                comparisonCard(previous)
            }
            if let source = night.sourceName {
                Label {
                    Text("Fuente: \(source)")
                } icon: {
                    Image(systemName: "applewatch")
                }
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle(Text("Noche"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.reloadKey) {
            let end = Calendar.current.date(byAdding: .day, value: -1, to: night.day) ?? night.day
            previous = await model.provider.sleepNights(endingOn: end, days: 28)
        }
    }

    private func comparisonCard(_ previous: [SleepNight]) -> some View {
        let average = previous.map(\.asleep).reduce(0, +) / Double(previous.count)
        let difference = night.asleep - average
        let staged = previous.filter(\.hasStages)
        return HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Frente a tu media", eyebrow: HalsynLexicon.tid.rawValue)
                comparisonRow(title: "Dormido", value: night.asleep, average: average)
                if night.hasStages && !staged.isEmpty {
                    ForEach([SleepSample.Stage.asleepDeep, .asleepREM], id: \.self) { stage in
                        let stageAverage = staged.map { $0.stages[stage] ?? 0 }.reduce(0, +) / Double(staged.count)
                        comparisonRow(title: stage.title, value: night.stages[stage] ?? 0, average: stageAverage)
                    }
                }
                Text(differenceText(difference))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                Text("Media de las 4 semanas anteriores a esta noche.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private func differenceText(_ difference: TimeInterval) -> LocalizedStringKey {
        let amount = sleepText(abs(difference))
        if abs(difference) < 15 * 60 { return "Una noche en tu media." }
        return difference > 0 ? "Dormiste \(amount) más que tu media." : "Dormiste \(amount) menos que tu media."
    }

    private func comparisonRow(title: String, value: TimeInterval, average: TimeInterval) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .foregroundStyle(.halsynPrimaryText)
            Spacer()
            Text(verbatim: sleepText(value))
                .monospacedDigit()
                .foregroundStyle(.halsynPrimaryText)
            Text(verbatim: "/ " + sleepText(average))
                .monospacedDigit()
                .foregroundStyle(.halsynSecondaryText)
        }
        .font(.halsynCaption)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Regularidad

/// Índice de regularidad del sueño (SRI) con su contexto en UK Biobank.
struct SleepRegularityCard: View {
    let nights: [SleepNight]

    var body: some View {
        let index = SleepRegularityIndex.compute(nights, calendar: .current)
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Regularidad del sueño", eyebrow: HalsynLexicon.tid.rawValue)
                if let index {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: HalsynFormat.integer(index.value))
                            .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: "/ 100")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                        Spacer()
                        Text(verdict(index.value))
                            .font(.halsynCaption.weight(.semibold))
                            .foregroundStyle(index.value < SleepRegularityIndex.studyInterquartileRange.lowerBound ? Color.halsynCaution : Color.halsynAccentText)
                    }
                    scale(index.value)
                    let pairs = index.pairs
                    Text("Probabilidad de estar dormido o despierto a la misma hora que el día anterior, de −100 a 100. Calculado con \(pairs) pares de noches seguidas.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Hacen falta al menos 6 noches seguidas registradas.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
                Text("En 60.977 adultos de UK Biobank, dormir con horarios regulares se asoció a un riesgo de mortalidad entre un 20 y un 48 por ciento menor que en el grupo más irregular, y predijo mejor que la duración del sueño. La mediana fue 81 y la mitad central estuvo entre 74 y 86.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Aquí solo cuenta el sueño nocturno (sin siestas) y el resultado varía según el método de cálculo: úsalo para ver tu evolución. Es una asociación observada, no un diagnóstico.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ReferenceLinks(references: [ScienceReferences.sleepRegularityMortality, ScienceReferences.sleepRegularityIndex])
            }
        }
    }

    private func verdict(_ value: Double) -> LocalizedStringKey {
        let range = SleepRegularityIndex.studyInterquartileRange
        if value > range.upperBound { return "Más regular que la mayoría" }
        if value >= range.lowerBound { return "En la mitad central" }
        return "Menos regular que la mayoría"
    }

    /// Escala 0–100 con la franja central del estudio y tu valor.
    private func scale(_ value: Double) -> some View {
        let range = SleepRegularityIndex.studyInterquartileRange
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.halsynHairline)
                Capsule()
                    .fill(Color.halsynChart.opacity(0.35))
                    .frame(width: width * (range.upperBound - range.lowerBound) / 100)
                    .offset(x: width * range.lowerBound / 100)
                Circle()
                    .fill(Color.halsynAccent)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, min(width - 12, width * max(0, value) / 100 - 6)))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
