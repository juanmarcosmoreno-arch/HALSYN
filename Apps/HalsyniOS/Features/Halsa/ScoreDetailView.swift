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
                    Text("La puntuación combina cinco dimensiones con pesos provisionales. Estar mejor que tu media no suma puntos extra y descansar no resta.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                    explanation("Sueño", weight: 25, "100 entre 7 y 9 h, la recomendación de la AASM y la SRS para adultos. Baja hasta 0 a las 4 h; dormir más de 9 h casi no resta (mínimo 70).")
                    explanation("Corazón", weight: 25, "FC en reposo y HRV de hoy frente a tu media de las 4 semanas anteriores. Solo resta alejarte en la dirección desfavorable (FC más alta o HRV más baja) más de una desviación típica.")
                    explanation("Movimiento", weight: 20, stepsText)
                    explanation("Ejercicio", weight: 15, "Minutos de ejercicio de los 7 días anteriores frente a 150 min por semana, el mínimo que recomienda la OMS para adultos.")
                    explanation("Equilibrio", weight: 15, "Carga de la última semana frente a la de las últimas 4. 100 entre 0,8 y 1,3 veces lo habitual; resta si subes de golpe. Peso bajo porque este cociente es discutido como predictor de lesiones.")
                    Text("Si faltan datos, solo se calcula con al menos el 60 % del peso disponible.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    Text("Es una estimación de bienestar, no una valoración clínica, y no está validada en estudios.")
                        .font(.halsynCaption.weight(.semibold))
                        .foregroundStyle(.halsynSecondaryText)
                    ReferenceLinks(references: [ScienceReferences.sleepDuration, ScienceReferences.dailySteps, ScienceReferences.physicalActivity, ScienceReferences.trainingLoad])
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

    private var stepsText: LocalizedStringKey {
        let age = ReferenceProfileStore.shared.age
        let steps = HalsynFormat.integer(HealthScoreConfiguration.stepsReference(age: age))
        guard let age else {
            return "Media de pasos de los 7 días anteriores frente a \(steps) al día. Añade tu fecha de nacimiento en Perfil para usar la referencia de tu edad."
        }
        return age >= 60
            ? "Media de pasos de los 7 días anteriores frente a \(steps) al día: en mayores de 60 años el beneficio sobre la mortalidad se estabiliza entre 6.000 y 8.000 pasos (Paluch et al., 2022)."
            : "Media de pasos de los 7 días anteriores frente a \(steps) al día: en menores de 60 años el beneficio sobre la mortalidad se estabiliza entre 8.000 y 10.000 pasos (Paluch et al., 2022)."
    }

    private func explanation(_ title: String, weight: Int, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(title))
                Text(verbatim: "· \(weight) %")
            }
            .font(.halsynCaption.weight(.semibold))
            .foregroundStyle(.halsynPrimaryText)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
