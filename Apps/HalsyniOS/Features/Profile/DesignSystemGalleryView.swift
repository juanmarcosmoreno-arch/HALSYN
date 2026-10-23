import HalsynCore
import HalsynDesign
import SwiftUI

/// Catálogo visual de los componentes, para revisar el design system en los
/// modos claro y oscuro. Todos los valores son de ejemplo.
struct DesignSystemGalleryView: View {
    @State private var progress = 0.62

    private static let sampleTrend: [DailyValue] = {
        let today = Calendar.current.startOfDay(for: .now)
        let values: [Double] = [52, 54, 53, 55, 51, 50, 52]
        return values.enumerated().compactMap { index, value in
            Calendar.current.date(byAdding: .day, value: index - values.count + 1, to: today).map { DailyValue(day: $0, value: value) }
        }
    }()

    var body: some View {
        HalsynScreen {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.l) {
                    HalsynSectionHeader("Logotipo", eyebrow: "MARCA")
                    HalsynLogo(.horizontal, height: 56)
                    HStack(spacing: HalsynSpacing.l) {
                        HalsynLogo(.vertical, height: 56)
                        HalsynSymbol(style: .monochrome(.halsynPrimaryText)).frame(height: 56)
                        HalsynLogo(.compact, height: 24)
                    }
                    Text("Símbolo vectorial aproximado a la referencia aprobada; pendiente de sustituir por el vector definitivo del diseñador.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }

            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynSectionHeader("Colores", eyebrow: "TOKENS")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: HalsynSpacing.s) {
                        swatch("background", .halsynBackground)
                        swatch("surface", .halsynSurface)
                        swatch("primaryText", .halsynPrimaryText)
                        swatch("secondaryText", .halsynSecondaryText)
                        swatch("accent", .halsynAccent)
                        swatch("accentText", .halsynAccentText)
                        swatch("accentSoft", .halsynAccentSoft)
                        swatch("brandDeep", .halsynBrandDeep)
                        swatch("positive", .halsynPositive)
                        swatch("caution", .halsynCaution)
                        swatch("alert", .halsynAlert)
                    }
                }
            }

            HalsynCard {
                VStack(spacing: HalsynSpacing.l) {
                    HalsynSectionHeader("Anillo y métricas", eyebrow: "COMPONENTES")
                    HStack(spacing: HalsynSpacing.l) {
                        HalsynScoreRing(score: 82, caption: "Buena condición").frame(width: 150)
                        HalsynScoreRing(score: nil, caption: "Sin datos", lineWidth: 8).frame(width: 90)
                    }
                    HStack {
                        HalsynMetricTile(title: "FC reposo", systemImage: "heart", value: "54", unit: "lpm")
                        HalsynMetricTile(title: "HRV", systemImage: "waveform.path.ecg", value: nil, unit: "ms", status: "Acceso no concedido")
                    }
                    HalsynProgressBar(progress: progress)
                    Slider(value: $progress, in: 0...1)
                    VStack(alignment: .leading, spacing: HalsynSpacing.xs) {
                        HalsynStatusIndicator(.positive, text: "Dentro de tu rango habitual")
                        HalsynStatusIndicator(.neutral, text: "Sin datos suficientes")
                        HalsynStatusIndicator(.caution, text: "Por encima de tu rango")
                        HalsynStatusIndicator(.alert, text: "Error de sincronización")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HalsynTrendChart(values: Self.sampleTrend, title: "FC reposo").frame(height: 120)
                    HalsynPrimaryButton("Botón principal", systemImage: "figure.run") {}
                    HalsynDemoBadge()
                }
            }

            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynSectionHeader("Estados", eyebrow: "VACÍO · CARGA")
                    HalsynEmptyState(systemImage: "moon", title: "Sin datos de sueño", message: "Lleva el Apple Watch al dormir para ver tu descanso.")
                    HalsynLoadingState()
                }
            }

            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HalsynSectionHeader("Pantallas de entrenamiento", eyebrow: "WATCH")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: HalsynSpacing.m) {
                            ForEach(WorkoutScreenProfile.defaults) { profile in
                                VStack(spacing: HalsynSpacing.xs) {
                                    WatchScreenPreview(profile: profile).frame(width: 140)
                                    Text(verbatim: profile.name).font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Design system")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: HalsynRadius.small, style: .continuous)
                .fill(color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: HalsynRadius.small, style: .continuous).strokeBorder(Color.halsynHairline, lineWidth: 0.5))
            Text(verbatim: name)
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { DesignSystemGalleryView() }
}
