import HalsynCore
import HalsynDesign
import SwiftUI

/// Fuerza para corredores: ejercicios para los días de gimnasio, para llevarle
/// a quien te entrena (ajusta el peso y la técnica).
struct RunnerStrengthView: View {
    var body: some View {
        HalsynScreen {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HalsynSectionHeader("Fuerza para corredores", eyebrow: HalsynLexicon.kraft.rawValue)
                    Text("Dos sesiones por semana de 30–40 min, lejos de las series y del umbral (el plan ya lo tiene en cuenta). Mejor pocas repeticiones con buena técnica y peso que muchas livianas.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(StrengthExercise.Group.allCases, id: \.self) { group in
                groupCard(group)
            }
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    ExpandableText("La fuerza con cargas y la pliometría mejoran la economía de carrera (gastas menos energía al mismo ritmo) sin aumentar el peso, y el trabajo de fuerza reduce las lesiones deportivas. El peso, las series y la técnica los ajusta quien te entrena; si algo duele, para.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    ReferenceLinks(references: [ScienceReferences.strengthForRunners, ScienceReferences.strengthInjuryPrevention])
                }
            }
        }
        .navigationTitle("Fuerza para corredores")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func groupCard(_ group: StrengthExercise.Group) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                Label(LocalizedStringKey(group.title), systemImage: group.symbol)
                    .font(.halsynHeadline)
                    .foregroundStyle(.halsynPrimaryText)
                Text(LocalizedStringKey(group.purpose))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                ForEach(StrengthExercise.exercises(in: group)) { exercise in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LocalizedStringKey(exercise.name))
                                .font(.halsynBody.weight(.semibold))
                            Spacer()
                            Text(LocalizedStringKey(exercise.dose))
                                .font(.halsynCaption.monospacedDigit())
                                .foregroundStyle(.halsynAccentText)
                        }
                        Text(LocalizedStringKey(exercise.howTo))
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
