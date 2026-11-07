import HalsynCore
import HalsynDesign
import SwiftUI

/// "Con tu forma actual": tiempos estimados para 5 km, 10 km, media y maratón.
struct RacePredictionCard: View {
    let predictions: [RacePrediction]
    var performance: PerformanceAssessment?
    /// Carreras limpias (para recalcular en el detalle al cambiar el exponente).
    var runs: [WorkoutSummary] = []
    let unitSystem: UnitSystem

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HalsynSectionHeader("Con tu forma actual", eyebrow: HalsynLexicon.fart.rawValue)
                if predictions.isEmpty {
                    Text("Con 3 carreras de 3 km o más en los últimos 90 días, HÅLSYN estima tus tiempos para 5 km, 10 km, media maratón y maratón.")
                        .font(.halsynBody)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(predictions) { prediction in
                        row(prediction)
                        if prediction.id != predictions.last?.id { Divider() }
                    }
                    if let performance {
                        Text(verbatim: "VDOT \(RaceGoalText.vdot(performance.currentVDOT)) · \(GoalProbabilityText.confidence(performance.confidence))")
                            .font(.halsynCaption.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                        NavigationLink {
                            PredictionDetailView(runs: runs, initial: performance)
                        } label: {
                            Label("Cómo se calcula y qué pruebas usa", systemImage: "function")
                                .font(.halsynCaption.weight(.semibold))
                        }
                    } else {
                        ExpandableText("Fórmula de Riegel con tus 3 mejores carreras recientes (de \(predictions[0].basedOn)). Supone que entrenas para esa distancia y vas a tope; si casi nunca corres fuerte, los tiempos reales pueden ser mejores. Con un test o una competición registrados, HÅLSYN usa un modelo más completo.")
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func row(_ prediction: RacePrediction) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(prediction.distance.title))
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Text(verbatim: "\(prediction.pace.formatted(in: unitSystem)) \(unitSystem.paceUnitSymbol)")
                    .font(.halsynCaption.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: HalsynFormat.duration(prediction.time))
                    .font(.halsynMetricValue)
                    .foregroundStyle(.halsynPrimaryText)
                if prediction.slowest - prediction.fastest > 1 {
                    Text(verbatim: "\(HalsynFormat.duration(prediction.fastest))–\(HalsynFormat.duration(prediction.slowest))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.halsynSecondaryText)
                }
                if prediction.isLongExtrapolation {
                    Label("Poco fiable: tus carreras son mucho más cortas", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.halsynCaution)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Detalle de la predicción: métodos, pruebas usadas, tendencia y exponente.
struct PredictionDetailView: View {
    let runs: [WorkoutSummary]
    let initial: PerformanceAssessment
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage(FitnessStore.riegelExponentKey) private var exponent = RacePerformanceModel.defaultRiegelExponent

    var body: some View {
        // Se recalcula al cambiar el exponente (lo lee de los ajustes).
        let performance = exponent > 0 ? (FitnessStore.shared.performance(runs: runs) ?? initial) : initial
        Form {
            Section {
                ForEach(Array(PredictionExplanationText.paragraphs(performance, runs: runs, unit: unitSystem).enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(.halsynCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("¿Por qué HÅLSYN estima este tiempo?")
            }

            Section {
                LabeledContent("Forma (VDOT)", value: RaceGoalText.vdot(performance.currentVDOT))
                LabeledContent("Incertidumbre", value: "± " + HalsynFormat.decimal(performance.uncertainty, fractionDigits: 1))
                if let trend = performance.weeklyTrend {
                    LabeledContent("Tendencia", value: (trend >= 0 ? "+" : "−") + HalsynFormat.decimal(abs(trend), fractionDigits: 2) + " / " + String(localized: "semana"))
                }
                LabeledContent("Confianza", value: GoalProbabilityText.confidence(performance.confidence))
            } footer: {
                Text("El VDOT es tu forma de carrera calculada con las fórmulas de Daniels a partir de esfuerzos a tope. No es el VO₂ máx. que estima el Apple Watch: están relacionados, pero se miden distinto.")
            }

            Section {
                ForEach(RaceDistance.allCases) { distance in
                    let prediction = performance.predict(distance.rawValue)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(LocalizedStringKey(distance.title)).font(.halsynHeadline)
                            Spacer()
                            Text(verbatim: HalsynFormat.duration(prediction.time)).font(.halsynHeadline.monospacedDigit())
                        }
                        Text(verbatim: "Daniels \(HalsynFormat.duration(prediction.vdotTime)) · Riegel \(HalsynFormat.duration(prediction.riegelTime))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.halsynSecondaryText)
                        if prediction.methodGap > 0.03 {
                            Label("Los métodos difieren más de un 3 %: la predicción es menos segura.", systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.halsynCaution)
                        }
                    }
                }
            } header: {
                Text("Métodos")
            } footer: {
                Text("Daniels proyecta tu VDOT de hoy a cada distancia. Riegel proyecta cada prueba con T₂ = T₁ × (D₂/D₁)^k; las pruebas de distancia parecida pesan más. El tiempo mostrado combina los dos.")
            }

            Section {
                Stepper(value: $exponent, in: RacePerformanceModel.plausibleExponent, step: 0.01) {
                    LabeledContent("Exponente k", value: HalsynFormat.decimal(exponent, fractionDigits: 2))
                }
                if let personal = performance.personalExponent {
                    LabeledContent("Tu exponente (de tus pruebas)", value: HalsynFormat.decimal(personal, fractionDigits: 3))
                }
            } header: {
                Text("Riegel")
            } footer: {
                Text(performance.personalExponent == nil
                     ? LocalizedStringKey("1,06 es el valor clásico. Con dos competiciones o tests a distancias bastante distintas, HÅLSYN calcula el tuyo y lo usa.")
                     : LocalizedStringKey("Se usa tu exponente porque sale de tus propias pruebas."))
            }

            Section {
                NavigationLink {
                    ModelAccuracyView(runs: runs)
                } label: {
                    Label("Precisión del modelo contigo", systemImage: "scope")
                }
            }

            Section {
                ForEach(performance.evidence) { item in
                    HStack {
                        Image(systemName: icon(item.kind))
                            .foregroundStyle(item.role == .counted ? Color.halsynAccentText : Color.halsynSecondaryText)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(SessionText.distance(item.distance, unit: unitSystem)) · \(HalsynFormat.duration(item.time))")
                                .font(.halsynCaption.monospacedDigit())
                            Text(item.date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                            Text(verbatim: roleText(item))
                                .font(.caption2)
                                .foregroundStyle(item.role == .counted ? Color.halsynSecondaryText : Color.halsynCaution)
                                .fixedSize(horizontal: false, vertical: true)
                            if let factors = item.factors, item.weight > 0 {
                                Text(verbatim: PredictionExplanationText.factors(factors))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.halsynSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: "VDOT " + RaceGoalText.vdot(item.vdot))
                                .font(.halsynCaption.monospacedDigit())
                            Text(verbatim: String(localized: "peso") + " " + HalsynFormat.decimal(item.weight, fractionDigits: 2))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                }
            } header: {
                Text("Pruebas usadas")
            } footer: {
                Text("Competiciones y tests registrados (180 días) y entrenamientos al aire libre a tope con pulso alto sostenido (42 días). Un test o una competición más lentos sí bajan la estimación; un entrenamiento, nunca. Peso = tipo (competición 1, test 0,9, entrenamiento 0,5) × antigüedad (la mitad cada 6 semanas) × distancia (menos de 1,5 km 0,6; de 1,5 a 3 km 0,85) × calidad (cinta 0,8; pulso bajo para un test 0,7). Los entrenamientos suman como mucho la mitad del peso de los tests.")
            }
        }
        .navigationTitle("Predicción")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Por qué cuenta (o no) cada prueba.
    private func roleText(_ item: PerformanceEvidence) -> String {
        switch item.role {
        case .counted:
            switch item.kind {
            case .race: return String(localized: "Competición: prioridad alta.")
            case .test: return String(localized: "Test: prioridad alta.")
            case .trainingEffort: return String(localized: "Entrenamiento a tope (pulso alto sostenido) que supera tus tests: suma.")
            }
        case .belowEstimate:
            return String(localized: "Entrenamiento por debajo de tu forma: no la baja (un rodaje más lento no significa que perdiste capacidad).")
        case .duplicate:
            return String(localized: "Mismo esfuerzo registrado dos veces: cuenta una sola vez.")
        case .inconsistent:
            return String(localized: "No encaja con tus otras pruebas: pesa menos.")
        }
    }

    private func icon(_ kind: PerformanceEvidence.Kind) -> String {
        switch kind {
        case .race: "flag.checkered"
        case .test: "stopwatch"
        case .trainingEffort: "figure.run"
        }
    }
}

/// Explicación en palabras del cálculo real (mismos números que el modelo).
enum PredictionExplanationText {
    static func paragraphs(_ performance: PerformanceAssessment, runs: [WorkoutSummary], unit: UnitSystem) -> [String] {
        var lines: [String] = []
        let counted = performance.countedEvidence
        let vdot = RaceGoalText.vdot(performance.currentVDOT)
        if counted.count == 1, let only = counted.first {
            let date = only.date.formatted(.dateTime.day().month(.abbreviated))
            let distance = SessionText.distance(only.distance, unit: unit)
            lines.append(String(localized: "Tu VDOT de \(vdot) sale de una sola prueba: \(distance) en \(HalsynFormat.duration(only.time)) el \(date)."))
        } else if counted.count > 1 {
            let terms = counted.map { item in
                RaceGoalText.vdot(item.valueUsed ?? item.vdot) + " × " + HalsynFormat.decimal(item.weight, fractionDigits: 2)
            }.joined(separator: " + ")
            let totalText = HalsynFormat.decimal(counted.map(\.weight).reduce(0, +), fractionDigits: 2)
            let count = counted.count
            lines.append(String(localized: "Tu VDOT de \(vdot) es una media ponderada de \(count) pruebas: (\(terms)) ÷ \(totalText). Por eso no coincide con el VDOT de ninguna prueba en particular."))
        }
        if performance.weeklyTrend != nil, !performance.trendIsProvisional {
            lines.append(String(localized: "Cada prueba se lleva a hoy con tu tendencia antes de promediar."))
        } else {
            lines.append(String(localized: "Sin tendencia: hacen falta 3 tests o competiciones en 3 semanas o más. Cada prueba entra con su VDOT tal cual."))
        }
        let excluded = performance.evidence.filter { $0.weight == 0 }.count
        if excluded > 0 {
            let excludedText = String(excluded)
            lines.append(String(localized: "Pruebas que no cuentan: \(excludedText) (abajo, el motivo de cada una)."))
        }
        if let plan = TrainingPlanStore.shared.plan,
           let probability = GoalProbability.evaluate(plan: plan, performance: performance, runs: runs, today: .now, calendar: .current) {
            let distance = String(localized: String.LocalizationValue(plan.goal.distance.title))
            let gain = HalsynFormat.decimal(probability.expectedGain, fractionDigits: 1)
            lines.append(String(localized: "\(distance) hoy: \(HalsynFormat.duration(probability.currentTime)). El día de la carrera, con la mejora esperada del escenario central (+\(gain) VDOT, según tu cumplimiento y el tiempo que falta): \(HalsynFormat.duration(probability.projectedTime))."))
        }
        let confidence = GoalProbabilityText.confidence(performance.confidence)
        lines.append(String(localized: "Límites: \(confidence). Los rangos son orientativos: no están calibrados con tus resultados reales. Daniels y Riegel son fórmulas de población; tu respuesta puede ser distinta."))
        return lines
    }

    static func factors(_ f: PerformanceEvidence.WeightFactors) -> String {
        var parts = [
            String(localized: "tipo") + " " + HalsynFormat.decimal(f.kind, fractionDigits: 2),
            String(localized: "antigüedad") + " " + HalsynFormat.decimal(f.age, fractionDigits: 2),
            String(localized: "distancia") + " " + HalsynFormat.decimal(f.distance, fractionDigits: 2),
            String(localized: "calidad") + " " + HalsynFormat.decimal(f.quality, fractionDigits: 2),
        ]
        if f.cap < 1 { parts.append(String(localized: "tope") + " " + HalsynFormat.decimal(f.cap, fractionDigits: 2)) }
        if f.consistency < 1 { parts.append(String(localized: "coherencia") + " " + HalsynFormat.decimal(f.consistency, fractionDigits: 2)) }
        var text = parts.joined(separator: " × ")
        for note in f.qualityNotes {
            switch note {
            case .treadmill: text += " · " + String(localized: "en cinta: distancia estimada")
            case .lowHeartRate: text += " · " + String(localized: "pulso bajo para un test: quizá no fue a tope")
            }
        }
        return text
    }
}
