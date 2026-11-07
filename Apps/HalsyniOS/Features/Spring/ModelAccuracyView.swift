import HalsynCore
import HalsynDesign
import SwiftUI

/// Cuánto acierta el modelo contigo: cada test o competición se predijo solo
/// con los datos anteriores a ese día y se compara con tu tiempo real.
struct ModelAccuracyView: View {
    let runs: [WorkoutSummary]
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var fitness: FitnessStore { .shared }

    var body: some View {
        let backtest = fitness.backtest(runs: runs)
        let outcomes = fitness.goalOutcomes
        Form {
            Section {
                Text("Cada test o competición que registraste se predice con lo que HÅLSYN sabía antes de ese día, sin mirar el resultado, y se compara con tu tiempo real. Así se mide cuánto acierta el modelo contigo.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            Section {
                LabeledContent(String(localized: "Pruebas evaluadas"), value: String(backtest.count))
                if let mae = backtest.meanAbsoluteError, let percent = backtest.meanAbsolutePercentageError {
                    LabeledContent(String(localized: "Error medio (MAE)"), value: "\(HalsynFormat.duration(mae)) · \(HalsynFormat.decimal(percent * 100, fractionDigits: 1)) %")
                }
                if let rmse = backtest.rootMeanSquareError {
                    LabeledContent(String(localized: "Error cuadrático (RMSE)"), value: HalsynFormat.duration(rmse))
                }
                if let bias = backtest.bias {
                    LabeledContent(String(localized: "Sesgo"), value: biasText(bias))
                }
                if let coverage = backtest.coverage {
                    LabeledContent(String(localized: "Dentro del rango del 80 %"), value: "\(Int((coverage * 100).rounded())) %")
                }
                if let calibrated = backtest.calibratedRelativeError {
                    LabeledContent(String(localized: "Error típico usado en los rangos"), value: "± \(HalsynFormat.decimal(calibrated * 100, fractionDigits: 1)) %")
                }
            } header: {
                Text("Predicción de tiempos")
            } footer: {
                Text(backtest.count < PredictionBacktest.minimumCasesForCalibration
                     ? LocalizedStringKey("Con 5 pruebas evaluadas o más, los rangos de las predicciones se ajustan a tu error real. Cada test que registres suma.")
                     : LocalizedStringKey("Sesgo positivo: el modelo te ve más lento de lo que corres (pesimista); negativo: optimista. Un rango bien calibrado contiene cerca del 80 % de los tiempos reales."))
            }
            if !backtest.cases.isEmpty {
                Section("Pruebas") {
                    ForEach(Array(backtest.cases.reversed())) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: SessionText.distance(item.distance, unit: unitSystem))
                                    .font(.halsynCaption.weight(.semibold))
                                Text(item.date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption2)
                                    .foregroundStyle(.halsynSecondaryText)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: String(localized: "Real \(HalsynFormat.duration(item.actual)) · previsto \(HalsynFormat.duration(item.predicted))"))
                                    .font(.caption.monospacedDigit())
                                Text(verbatim: (item.error >= 0 ? "+" : "−") + HalsynFormat.duration(abs(item.error)))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(abs(item.relativeError) <= 0.02 ? Color.halsynPositive : Color.halsynSecondaryText)
                            }
                        }
                    }
                }
            }
            Section {
                LabeledContent(String(localized: "Objetivos con resultado"), value: "\(outcomes.count) / \(GoalCalibration.minimumOutcomes)")
                if let brier = GoalCalibration.brierScore(outcomes) {
                    LabeledContent(String(localized: "Puntuación de Brier"), value: HalsynFormat.decimal(brier, fractionDigits: 3))
                }
            } header: {
                Text("Factibilidad del objetivo")
            } footer: {
                Text("La factibilidad se muestra como categoría hasta tener al menos 5 objetivos corridos y una puntuación de Brier menor que 0,25 (0 es perfecto; 0,25 es lo que da decir siempre 50 %). Un objetivo cuenta cuando registras como competición la carrera del plan.")
            }
        }
        .navigationTitle("Precisión del modelo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func biasText(_ bias: TimeInterval) -> String {
        let amount = HalsynFormat.duration(abs(bias))
        if abs(bias) < 3 { return String(localized: "Sin sesgo") }
        return bias > 0 ? String(localized: "\(amount) pesimista") : String(localized: "\(amount) optimista")
    }
}
