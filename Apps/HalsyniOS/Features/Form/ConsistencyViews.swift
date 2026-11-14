import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Datos de la app para la constancia: plan, días de enfermedad o lesión y semanas livianas.
@MainActor
enum ConsistencyBuilder {
    static func build(runs: [WorkoutSummary]) -> ConsistencyReport {
        let calendar = Calendar.current
        let now = Date.now
        let onlyRuns = runs.filter(\.activity.isRun)
        let plan = TrainingPlanStore.shared.displayPlan
        // Objetivo: el del plan; sin plan, tu mediana de carreras por semana (12 semanas, mínimo 2).
        let target: Int
        if let plan {
            target = plan.goal.runsPerWeek
        } else {
            let counts: [Int] = (1...12).compactMap { offset in
                guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: now),
                      let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
                return onlyRuns.filter { $0.start >= start && $0.start < end }.count
            }.sorted()
            target = max(counts.isEmpty ? 2 : counts[counts.count / 2], 2)
        }
        var excused = HealthEventStore.shared.trainingAffectedDays()
        for (day, reason) in SessionSkipStore.shared.skips where reason.isExcused { excused.insert(calendar.startOfDay(for: day)) }
        let light = Set((plan?.weeks ?? []).filter { $0.phase == .recovery || $0.phase == .taper || $0.phase == .race }.map(\.start))
        let adherence = plan.map {
            TrainingAdherence.evaluate(plan: $0, runs: onlyRuns, today: now, calendar: calendar, skips: SessionSkipStore.shared.skips, healthDays: HealthEventStore.shared.trainingAffectedDays()).planAdherence
        } ?? nil
        return ConsistencyEngine.evaluate(
            runs: onlyRuns.map { ($0.start, $0.distanceMeters ?? 0) },
            targetPerWeek: target,
            excusedDays: excused,
            lightWeekStarts: light,
            planAdherence: adherence,
            today: now,
            calendar: calendar
        )
    }
}

enum ConsistencyText {
    static func component(_ component: ConsistencyReport.Component) -> String {
        switch component {
        case .frequency: String(localized: "Frecuencia")
        case .regularity: String(localized: "Regularidad")
        case .stability: String(localized: "Estabilidad del volumen")
        case .plan: String(localized: "Plan cumplido")
        }
    }

    static func explanation(_ component: ConsistencyReport.Component, target: Int) -> String {
        let targetText = String(target)
        switch component {
        case .frequency: return String(localized: "Carreras por semana frente a \(targetText).")
        case .regularity: return String(localized: "Semanas con el mínimo de carreras (en las de descarga basta una).")
        case .stability: return String(localized: "Qué tan parejos son tus kilómetros semana a semana.")
        case .plan: return String(localized: "Sesiones del plan hechas (las de enfermedad o lesión no cuentan).")
        }
    }
}

/// Fila de Rendimiento.
struct ConsistencyAreaLink: View {
    let runs: [WorkoutSummary]

    var body: some View {
        let report = ConsistencyBuilder.build(runs: runs)
        FormAreaLink(title: "Constancia", subtitle: subtitle(report), systemImage: "calendar.badge.checkmark") {
            ConsistencyView(report: report)
        }
    }

    private func subtitle(_ report: ConsistencyReport) -> String {
        let streakText = String(report.streakWeeks)
        if let score = report.score {
            let scoreText = String(score)
            return String(localized: "Puntaje \(scoreText) de 100 · \(streakText) semanas seguidas")
        }
        return String(localized: "Regularidad del entrenamiento, semana a semana")
    }
}

struct ConsistencyView: View {
    let report: ConsistencyReport
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        HalsynScreen {
            Text("¿Entrenas con regularidad, más allá de cumplir el plan?")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
                .padding(.top, HalsynSpacing.s)
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Constancia", eyebrow: HalsynLexicon.tid.rawValue)
                    if let score = report.score {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: String(score))
                                .font(.halsynMetricValue)
                                .foregroundStyle(.halsynPrimaryText)
                            Text("de 100")
                                .font(.halsynCaption)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                        ForEach(report.parts, id: \.component) { part in
                            VStack(alignment: .leading, spacing: 2) {
                                LabeledContent {
                                    Text(verbatim: "\(Int((part.value * 100).rounded())) %")  // nolocalize
                                        .monospacedDigit()
                                } label: {
                                    let weightText = String(Int((part.weight * 100).rounded()))
                                    Text("\(ConsistencyText.component(part.component)) (peso \(weightText) %)")
                                }
                                .font(.halsynCaption)
                                Text(verbatim: ConsistencyText.explanation(part.component, target: report.targetPerWeek))
                                    .font(.caption2)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                        }
                    } else {
                        Text("Hacen falta 4 semanas con datos para calcular el puntaje.")
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    let streakText = String(report.streakWeeks)
                    LabeledContent(String(localized: "Semanas seguidas corriendo"), value: streakText)
                        .font(.halsynCaption)
                    let gapsText = String(report.interruptions)
                    LabeledContent(String(localized: "Pausas de 10 días o más (12 semanas)"), value: gapsText)
                        .font(.halsynCaption)
                }
            }
            if !report.weeks.isEmpty {
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                        Text("Carreras por semana")
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        let normal = String(localized: "Normal")
                        let light = String(localized: "Descarga del plan")
                        let sick = String(localized: "Enfermedad o lesión")
                        Chart {
                            ForEach(report.weeks) { week in
                                BarMark(x: .value("Semana", week.start, unit: .weekOfYear), y: .value("Carreras", week.runs))
                                    .foregroundStyle(by: .value("Tipo", week.excused ? sick : (week.light ? light : normal)))
                            }
                            RuleMark(y: .value("Objetivo", report.targetPerWeek))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(Color.halsynPrimaryText.opacity(0.5))
                        }
                        .chartForegroundStyleScale([normal: Color.halsynChart, light: Color.halsynChart.opacity(0.45), sick: Color.halsynSecondaryText.opacity(0.4)])
                        .frame(height: 150)
                        let targetText = String(report.targetPerWeek)
                        Text("La línea es tu objetivo de \(targetText) carreras por semana (el del plan; sin plan, tu mediana de las últimas 12 semanas).")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Text("Cómo se calcula")
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    ExpandableText("Puntaje de 0 a 100 con las 8 semanas completas anteriores: frecuencia (35 %, carreras por semana frente al objetivo, como mucho el 100 %), regularidad (25 %, semanas con al menos el objetivo menos una carrera; en las de descarga, una), estabilidad (20 %, 1 menos el coeficiente de variación de los kilómetros semanales, sin semanas de descarga) y plan (20 %, sesiones cumplidas; sin plan, su peso se reparte). No penaliza las semanas con 4 días o más de enfermedad o lesión (se quitan), las de descarga o afinamiento del plan ni los descansos programados.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    Text(verbatim: "ConsistencyEngine \(ConsistencyEngine.version)")  // nolocalize
                        .font(.caption2.monospaced())
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .navigationTitle("Constancia")
        .navigationBarTitleDisplayMode(.inline)
    }
}
