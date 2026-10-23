import HalsynCore
import HalsynDesign
import SwiftUI

/// "Con tu forma actual": tiempos estimados para 5 km, 10 km, media y maratón.
struct RacePredictionCard: View {
    let predictions: [RacePrediction]
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
                    Text("Fórmula de Riegel con tus 3 mejores carreras recientes (de \(predictions[0].basedOn)). Supone que entrenas para esa distancia y vas a tope; si casi nunca corres fuerte, los tiempos reales pueden ser mejores. El rango refleja el error de la fórmula.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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
                Text(verbatim: "\(HalsynFormat.duration(prediction.fastest))–\(HalsynFormat.duration(prediction.slowest))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
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
