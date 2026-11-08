import Charts
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
        let projection = fitness.projectionBacktest(runs: runs)
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
                if backtest.count >= PredictionBacktest.minimumCasesForCalibration, let coverage = backtest.coverage {
                    LabeledContent(String(localized: "Dentro del rango del 80 %"), value: "\(Int((coverage * 100).rounded())) %")
                }
                if backtest.count >= PredictionBacktest.minimumCasesForCalibration, let calibrated = backtest.calibratedRelativeError {
                    LabeledContent(String(localized: "Error típico usado en los rangos"), value: "± \(HalsynFormat.decimal(calibrated * 100, fractionDigits: 1)) %")
                }
            } header: {
                Text("Rendimiento de hoy")
            } footer: {
                Text(backtest.count < PredictionBacktest.minimumCasesForCalibration
                     ? LocalizedStringKey("Con 5 pruebas evaluadas o más, los rangos de las predicciones se ajustan a tu error real. Cada test que registres suma.")
                     : LocalizedStringKey("Sesgo positivo: el modelo te ve más lento de lo que corres (pesimista); negativo: optimista. Un rango bien calibrado contiene cerca del 80 % de los tiempos reales."))
            }
            Section {
                LabeledContent(String(localized: "Pruebas evaluadas"), value: String(projection.count))
                if let mae = projection.meanAbsoluteError, let percent = projection.meanAbsolutePercentageError {
                    LabeledContent(String(localized: "Error medio (MAE)"), value: "\(HalsynFormat.duration(mae)) · \(HalsynFormat.decimal(percent * 100, fractionDigits: 1)) %")
                }
                if let bias = projection.bias {
                    LabeledContent(String(localized: "Sesgo"), value: biasText(bias))
                }
                if projection.count >= PredictionBacktest.minimumCasesForCalibration, let coverage = projection.coverage {
                    LabeledContent(String(localized: "Dentro del rango del 80 %"), value: "\(Int((coverage * 100).rounded())) %")
                }
            } header: {
                Text("Proyección a 4 semanas")
            } footer: {
                Text("Se proyecta cada test o competición desde 4 semanas antes, sin ver nada posterior. Valida la proyección por separado del rendimiento de hoy. La cobertura solo se muestra con 5 casos o más.")
            }
            Section {
                if !projection.hasEnoughData {
                    Text("Datos insuficientes para validar")
                        .font(.halsynCaption.weight(.semibold))
                }
                ForEach(projection.errorByHorizon, id: \.label) { group in
                    LabeledContent {
                        Text(verbatim: group.meanAbsoluteError.map { HalsynFormat.duration($0) } ?? "—")
                            .monospacedDigit()
                    } label: {
                        let label = group.label
                        let casesText = String(group.count)
                        Text("Horizonte \(label) · \(casesText) casos")
                    }
                }
            } header: {
                Text("Error por horizonte")
            } footer: {
                Text("Días entre el último resultado que veía el modelo y la prueba predicha. Con menos de 5 casos no se habla de precisión: cada número puede cambiar mucho con la próxima prueba.")
            }
            if backtest.cases.count >= 2 {
                Section("Evolución del error") {
                    Chart {
                        ForEach(backtest.cases) { item in
                            PointMark(x: .value("Fecha", item.date), y: .value("Error %", item.relativeError * 100))
                                .foregroundStyle(by: .value("Tipo", String(localized: "Hoy")))
                        }
                        ForEach(projection.cases) { item in
                            PointMark(x: .value("Fecha", item.date), y: .value("Error %", item.relativeError * 100))
                                .foregroundStyle(by: .value("Tipo", String(localized: "Proyección")))
                                .symbol(.square)
                        }
                        RuleMark(y: .value("Cero", 0))
                            .foregroundStyle(Color.halsynHairline)
                    }
                    .chartForegroundStyleScale([String(localized: "Hoy"): Color.halsynChart, String(localized: "Proyección"): Color.halsynHighlight])
                    .frame(height: 160)
                    Text("Por encima de 0: el modelo te veía más lento de lo que corriste.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
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
