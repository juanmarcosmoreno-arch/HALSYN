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
                Text("Competiciones y tests registrados (180 días) y entrenamientos al aire libre a tope con pulso alto sostenido (42 días). Los entrenamientos solo pueden subir la estimación, nunca bajarla; la cinta no se compara. El peso baja a la mitad cada 6 semanas.")
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
