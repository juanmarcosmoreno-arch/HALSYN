import Charts
import HalsynCore
import HalsynDesign
import SwiftUI

/// Textos del modelo de adaptación individual.
enum AdaptationText {
    static func state(_ estimate: AdaptationEstimate) -> String {
        switch estimate.state {
        case .reference: String(localized: "Adaptación individual: todavía no estimable")
        case .learning: String(localized: "Adaptación individual: aprendiendo")
        case .personalized: String(localized: "Adaptación individual: personalizada")
        }
    }

    static func rate(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "")  // nolocalize
        return sign + HalsynFormat.decimal(abs(value), fractionDigits: 2)
    }

    /// Detalle con números (para la pantalla y la exportación).
    static func lines(_ estimate: AdaptationEstimate) -> [String] {
        var lines: [String] = []
        let testsText = String(estimate.testsUsed), spanText = String(estimate.spanDays)
        switch estimate.state {
        case .reference:
            lines.append(String(localized: "Se necesitan al menos 3 tests o competiciones separados por 3 semanas o más. Ahora: \(testsText) en \(spanText) días. Se usa la referencia."))
        case .learning, .personalized:
            let effective = HalsynFormat.decimal(estimate.effectiveTests, fractionDigits: 1)
            lines.append(String(localized: "Pruebas usadas: \(testsText) en \(spanText) días (tamaño efectivo \(effective))."))
        }
        let referenceText = rate(estimate.referenceRate), referenceSD = HalsynFormat.decimal(estimate.referenceSD, fractionDigits: 2)
        lines.append(String(localized: "Referencia: \(referenceText) ± \(referenceSD) VDOT por semana (pauta de Daniels ajustada por cumplimiento y frecuencia)."))
        if let dataRate = estimate.dataRate, let dataSD = estimate.dataSD {
            let dataText = rate(dataRate), dataSDText = HalsynFormat.decimal(dataSD, fractionDigits: 2)
            lines.append(String(localized: "Solo con tus pruebas: \(dataText) ± \(dataSDText) VDOT por semana."))
        }
        let rateText = rate(estimate.rate), rateSD = HalsynFormat.decimal(estimate.rateSD, fractionDigits: 2)
        let individual = String(Int((estimate.individualWeight * 100).rounded())), reference = String(Int((estimate.referenceWeight * 100).rounded()))
        lines.append(String(localized: "Combinada: \(rateText) ± \(rateSD) VDOT por semana. Peso de tu evidencia: \(individual) %; de la referencia: \(reference) %."))
        if estimate.downweighted > 0 {
            let downText = String(estimate.downweighted)
            lines.append(String(localized: "Pruebas con menos peso por apartarse de la tendencia: \(downText)."))
        }
        return lines
    }
}

/// Puntos de VDOT, tendencia, proyección con su banda P10–P90, fecha de la carrera y objetivo.
struct PerformanceEvolutionChart: View {
    let performance: PerformanceAssessment
    let probability: GoalProbability
    let goal: PlanGoal

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let vdot: Double
        let counted: Bool
    }

    private struct BandPoint: Identifiable {
        let id = UUID()
        let date: Date
        let low: Double
        let mean: Double
        let high: Double
    }

    private var points: [Point] {
        performance.evidence.filter { $0.role != .duplicate && ($0.kind != .trainingEffort || $0.role == .counted) }.map {
            Point(date: $0.date, vdot: $0.vdot, counted: $0.role == .counted || $0.role == .inconsistent)
        }
    }

    private var band: [BandPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weeks = probability.central?.weeks ?? 0
        let compliance = probability.adherence?.projectionCompliance ?? probability.compliance
        let sessions = probability.adherence?.planned
        var result: [BandPoint] = []
        let steps = Array(Set(Array(stride(from: 0, through: weeks, by: max(1, weeks / 8))) + [weeks])).sorted()
        for step in steps {
            let projection = GoalProjection.project(performance: performance, weeks: step, compliance: compliance, runsPerWeek: goal.runsPerWeek, scenario: .central, complianceSessions: sessions)
            let date = step == weeks ? goal.raceDate : (calendar.date(byAdding: .day, value: step * 7, to: today) ?? today)
            let spread = 1.2816 * projection.uncertainty
            result.append(BandPoint(date: date, low: projection.meanVDOT - spread, mean: projection.meanVDOT, high: projection.meanVDOT + spread))
        }
        return result
    }

    var body: some View {
        let band = band
        let observed = String(localized: "Pruebas")
        let projected = String(localized: "Proyección")
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            Text("Evolución del rendimiento")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.halsynSecondaryText)
            Chart {
                ForEach(band) { item in
                    AreaMark(x: .value("Fecha", item.date), yStart: .value("P10", item.low), yEnd: .value("P90", item.high))
                        .foregroundStyle(Color.halsynChart.opacity(0.15))
                    LineMark(x: .value("Fecha", item.date), y: .value("VDOT", item.mean))
                        .foregroundStyle(by: .value("Serie", projected))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
                ForEach(points) { point in
                    PointMark(x: .value("Fecha", point.date), y: .value("VDOT", point.vdot))
                        .foregroundStyle(by: .value("Serie", observed))
                        .symbol(point.counted ? BasicChartSymbolShape.circle : BasicChartSymbolShape.cross)
                        .opacity(point.counted ? 1 : 0.45)
                }
                RuleMark(y: .value("Objetivo", probability.goalVDOT))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.halsynPrimaryText.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Objetivo").font(.caption2).foregroundStyle(.halsynSecondaryText)
                    }
                RuleMark(x: .value("Carrera", goal.raceDate))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.halsynHairline)
            }
            .chartForegroundStyleScale([observed: Color.halsynPrimaryText, projected: Color.halsynChart])
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            if let adaptation = probability.central?.adaptation {
                Text(verbatim: AdaptationText.state(adaptation))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.halsynSecondaryText)
            }
            ExpandableText("Puntos: el VDOT de cada test o competición (las cruces pesan poco o nada). Línea discontinua: lo esperado; la banda, entre el percentil 10 y el 90 de la distribución predictiva (sin calibrar con tus resultados). La línea vertical es la fecha de la carrera y la horizontal, el VDOT de tu objetivo. Lo observado y lo proyectado se dibujan distinto: lo proyectado no es un dato.")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                HowHalsynLearnsView(adaptation: probability.central?.adaptation, central: probability.central)
            } label: {
                Label("¿Cómo aprende HÅLSYN?", systemImage: "graduationcap")
                    .font(.halsynCaption.weight(.semibold))
            }
        }
    }
}

/// Qué aprende HÅLSYN de ti, con qué datos y con cuánta seguridad.
struct HowHalsynLearnsView: View {
    let adaptation: AdaptationEstimate?
    let central: GoalProjection.Result?

    var body: some View {
        Form {
            Section {
                Text("HÅLSYN parte de una referencia prudente (la pauta de Daniels: un punto de VDOT cada 6 semanas, ajustado por cuánto cumples el plan y cuántos días corres) y la corrige con tu propia evolución a medida que registras tests y competiciones. Cuánto pesa cada parte no está fijado: sale de cuánta información aportan tus datos frente a la incertidumbre de la referencia.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            if let adaptation {
                Section {
                    Text(verbatim: AdaptationText.state(adaptation))
                        .font(.halsynCaption.weight(.semibold))
                    ForEach(AdaptationText.lines(adaptation), id: \.self) { line in
                        Text(verbatim: line)
                            .font(.halsynCaption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ProgressView(value: adaptation.individualWeight) {
                        Text("Peso de tu evidencia")
                            .font(.caption2)
                    }
                } header: {
                    Text("Tu adaptación")
                }
            }
            if let central {
                Section {
                    ForEach(Array(Self.parts(central).enumerated()), id: \.offset) { _, part in
                        LabeledContent(part.0) {
                            Text(verbatim: "± " + HalsynFormat.decimal(part.1.squareRoot(), fractionDigits: 2))  // nolocalize
                                .monospacedDigit()
                        }
                    }
                    LabeledContent(String(localized: "Total (1 desviación)")) {
                        Text(verbatim: "± " + HalsynFormat.decimal(central.uncertainty, fractionDigits: 2))  // nolocalize
                            .monospacedDigit()
                    }
                } header: {
                    Text("De dónde sale la incertidumbre (VDOT)")
                } footer: {
                    Text("Las fuentes se suman como varianzas. Con pocos tests, la incertidumbre de la mejora domina: por eso cuatro sesiones no bastan para dar mucha confianza.")
                }
            }
            Section {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Text("Estados")
                        .font(.halsynCaption.weight(.semibold))
                    Text("Referencia: menos de 3 pruebas o menos de 3 semanas entre la primera y la última. Aprendiendo: hay datos, pero pesan menos que la referencia. Personalizada: tu evidencia pesa al menos tanto como la referencia, con 4 pruebas o más en 6 semanas o más.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Text("Cómo se protege de errores")
                        .font(.halsynCaption.weight(.semibold))
                    Text("Cada prueba pesa según su tipo, distancia y calidad, y la mitad cada 12 semanas de antigüedad. Una prueba que se aparta mucho de la tendencia pesa menos (Huber). Si tus pruebas varían más de lo que explica su ruido, la incertidumbre crece. La mejora semanal se limita a ±0,25 VDOT para no extrapolar. Tus datos pueden indicar que empeoras: el modelo no lo oculta.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    Text("Qué no usa todavía")
                        .font(.halsynCaption.weight(.semibold))
                    Text("La carga de entrenamiento y la continuidad no entran como predictores de tu mejora: con pocos tests no se puede estimar su efecto sin sobreajustar. Todo se calcula en el iPhone, sin servicios externos.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Cómo funciona")
            } footer: {
                Text("Referencias: Daniels J. Daniels' Running Formula (3.ª ed., 2014); Gelman A. et al. Bayesian Data Analysis (3.ª ed., 2013), cap. 2 y 14 (combinación de una referencia con datos por precisión); Huber P. J. Robust Statistics (1981); Kish L. Survey Sampling (1965), tamaño efectivo de muestra.")
            }
        }
        .navigationTitle("¿Cómo aprende HÅLSYN?")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }

    static func parts(_ result: GoalProjection.Result) -> [(String, Double)] {
        let names: [(String, String)] = [
            ("current", String(localized: "Tu forma actual")),
            ("rate", String(localized: "Tu ritmo de mejora")),
            ("adherence", String(localized: "Cumplimiento del plan")),
            ("horizon", String(localized: "Tiempo hasta la carrera")),
            ("raceDay", String(localized: "El día de la carrera")),
        ]
        return names.compactMap { key, name in result.varianceParts[key].map { (name, $0) } }
    }
}
