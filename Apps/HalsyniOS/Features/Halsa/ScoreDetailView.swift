import HalsynCore
import HalsynDesign
import SwiftUI

/// Desglose de la puntuación de un día: dimensiones, pesos, cobertura,
/// confianza, factores y cómo se calcula.
struct ScoreDetailView: View {
    let score: DailyScore

    var body: some View {
        HalsynScreen {
            HalsynCard {
                VStack(spacing: HalsynSpacing.m) {
                    HStack {
                        Text(verbatim: HalsynModule.halsa.brandName).halsynEyebrowStyle()
                        Spacer()
                        if score.origin.isDemo { HalsynDemoBadge() }
                    }
                    HalsynScoreRing(score: score.value, caption: score.band.title)
                        .frame(maxWidth: 200)
                    Text(score.day, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    if let breakdown = score.breakdown {
                        HStack(spacing: HalsynSpacing.m) {
                            Label {
                                Text(ScoreTexts.confidence(breakdown.confidence))
                            } icon: {
                                Image(systemName: "gauge.with.dots.needle.33percent")
                            }
                            let coverage = ScoreTexts.percent(breakdown.coverage)
                            Text("Datos disponibles: \(coverage)")
                        }
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    }
                    DataOriginFootnote(origin: score.origin)
                }
                .frame(maxWidth: .infinity)
            }

            if let breakdown = score.breakdown {
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                        HalsynSectionHeader("Dimensiones")
                        ForEach(breakdown.dimensions) { dimension in
                            dimensionRow(dimension)
                        }
                    }
                }

                if !breakdown.factors.isEmpty {
                    HalsynCard {
                        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                            HalsynSectionHeader("Qué ha influido")
                            ForEach(Array(breakdown.factors.enumerated()), id: \.offset) { _, factor in
                                ScoreFactorRow(factor: factor)
                            }
                        }
                    }
                }
            }

            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Cómo se calcula")
                    Text("La puntuación combina cinco dimensiones con pesos provisionales. Sueño frente a la recomendación de 7–9 h; FC en reposo y HRV frente a tu propia media de las últimas 4 semanas; pasos y minutos de ejercicio de los 7 días completos anteriores; y la carga reciente frente a tu carga habitual. Estar mejor que tu media no suma puntos extra y descansar no resta.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                    Text("Si faltan datos, solo se calcula con al menos el 60 % del peso disponible.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    Text("Es una estimación de bienestar, no una valoración clínica, y no está validada en estudios.")
                        .font(.halsynCaption.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                    if let version = score.breakdown?.engineVersion {
                        Text(verbatim: "HealthScoreEngine \(version)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.halsynSecondaryText)
                    }
                }
            }
        }
        .navigationTitle(Text("Puntuación"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dimensionRow(_ dimension: DimensionScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(LocalizedStringKey(dimension.dimension.title), systemImage: dimension.dimension.systemImage)
                    .font(.halsynCaption.weight(.semibold))
                    .foregroundStyle(.halsynPrimaryText)
                Spacer()
                if let value = dimension.score {
                    Text(verbatim: "\(value)")
                        .font(.halsynHeadline.monospacedDigit())
                        .foregroundStyle(.halsynPrimaryText)
                }
            }
            if let value = dimension.score {
                HalsynProgressBar(progress: Double(value) / 100)
            } else if let reason = dimension.missingReason {
                Text(ScoreTexts.missing(reason))
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
            }
            let weight = ScoreTexts.percent(dimension.weight)
            Text("Peso: \(weight)")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
