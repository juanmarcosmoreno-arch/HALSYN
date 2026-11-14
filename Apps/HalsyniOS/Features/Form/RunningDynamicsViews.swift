import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

enum RunningDynamicsText {
    static func value(_ metric: RunningDynamicsMetric, _ value: Double) -> String {
        HalsynFormat.decimal(value, fractionDigits: metric.fractionDigits) + " " + String(localized: String.LocalizationValue(metric.unit))  // nolocalize
    }

    static func change(_ summary: RunningDynamicsSummary) -> String? {
        guard let change = summary.change, let difference = summary.adjustedChange else { return nil }
        let amount = value(summary.metric, abs(difference))
        switch change {
        case .higher: return String(localized: "A igual velocidad, \(amount) más que hace 8 semanas.")
        case .lower: return String(localized: "A igual velocidad, \(amount) menos que hace 8 semanas.")
        case .unclear: return String(localized: "A igual velocidad, sin cambio claro frente a hace 8 semanas.")
        }
    }
}

/// Fila de Rendimiento.
struct RunningDynamicsAreaLink: View {
    let runs: [WorkoutSummary]

    var body: some View {
        let outdoor = runs.filter { $0.activity == .outdoorRun }
        let summaries = RunningDynamicsAnalysis.summaries(outdoor, today: .now, calendar: .current)
        FormAreaLink(title: "Técnica de carrera", subtitle: subtitle(summaries), systemImage: "figure.run.circle") {
            RunningDynamicsView(summaries: summaries)
        }
    }

    private func subtitle(_ summaries: [RunningDynamicsSummary]) -> String {
        guard let cadence = summaries.first(where: { $0.metric == .cadence }) else {
            return String(localized: "Cadencia, zancada, contacto y potencia")
        }
        let cadenceText = RunningDynamicsText.value(.cadence, cadence.recentMean)
        if let stride = summaries.first(where: { $0.metric == .strideLength }) {
            let strideText = RunningDynamicsText.value(.strideLength, stride.recentMean)
            return String(localized: "Cadencia \(cadenceText) · zancada \(strideText)")
        }
        return String(localized: "Cadencia \(cadenceText)")
    }
}

/// Técnica de carrera: medias de 28 días y cambios a igual velocidad.
struct RunningDynamicsView: View {
    let summaries: [RunningDynamicsSummary]

    var body: some View {
        HalsynScreen {
            Text("Cómo corres: pasos, zancada, apoyo y potencia. Describe tu forma de correr; no hay una técnica ideal para todos.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
                .padding(.top, HalsynSpacing.s)
            if summaries.isEmpty {
                HalsynCard {
                    Text("Todavía no hay datos: hacen falta 3 carreras al aire libre en los últimos 28 días. La zancada, el tiempo de contacto, la oscilación y la potencia las guarda el Apple Watch (Series 6, SE de 2.ª generación o posterior, con watchOS 9 o posterior) en las carreras al aire libre.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(summaries) { summary in
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                        Text(LocalizedStringKey(summary.metric.title))
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: RunningDynamicsText.value(summary.metric, summary.recentMean))
                                .font(.halsynMetricValue)
                                .foregroundStyle(.halsynPrimaryText)
                            Spacer()
                            let runsText = String(summary.recentRuns)
                            Text("\(runsText) carreras · 28 días")
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        if let change = RunningDynamicsText.change(summary) {
                            Text(verbatim: change)
                                .font(.halsynCaption)
                                .foregroundStyle(summary.change == .unclear ? Color.halsynSecondaryText : Color.halsynPrimaryText)
                        } else {
                            Text("Todavía no hay datos de hace 8 semanas para comparar.")
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        let recent = summary.series.suffix(30)
                        if recent.count >= 3 {
                            Chart {
                                ForEach(Array(recent.enumerated()), id: \.offset) { _, point in
                                    PointMark(x: .value("Fecha", point.day), y: .value("Valor", point.value))
                                        .foregroundStyle(Color.halsynChart)
                                }
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 110)
                        }
                        if summary.metric == .speedPerWatt {
                            Text("Indicador indirecto: velocidad por cada vatio. No mide la economía de carrera real, que necesita análisis de gases.")
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Text("Cómo se calcula")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    ExpandableText("Medias de cada carrera al aire libre que guardó el Apple Watch (en cinta la velocidad es estimada y no se usa). Al correr más rápido la cadencia, la zancada y el contacto cambian solos; por eso los cambios se comparan a igual velocidad: con todas tus carreras se ajusta una recta métrica–velocidad y se comparan los últimos 28 días con los 28 días que terminan 8 semanas antes. Solo se habla de cambio si supera 1,96 errores estándar. «Más» o «menos» no significa mejor o peor: una cadencia más alta o un contacto más corto no son mejoras por sí mismos.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    Text(verbatim: "RunningDynamicsAnalysis \(RunningDynamicsAnalysis.version)")  // nolocalize
                        .font(.caption2.monospaced())
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .navigationTitle("Técnica de carrera")
        .navigationBarTitleDisplayMode(.inline)
    }
}
