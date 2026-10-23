import HalsynCore
import HalsynDesign
import SwiftUI

/// Resumen de un entrenamiento. Fase 1: métricas agregadas. Ruta, vueltas,
/// zonas y gráficos llegan en las Fases 4–5.
struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    private let columns = [GridItem(.flexible(), spacing: HalsynSpacing.s), GridItem(.flexible(), spacing: HalsynSpacing.s)]

    var body: some View {
        HalsynScreen {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HStack {
                        Label(LocalizedStringKey(workout.activity.title), systemImage: workout.activity.systemImage)
                            .halsynEyebrowStyle()
                        Spacer()
                        if workout.origin.isDemo { HalsynDemoBadge() }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: workout.distanceMeters.map { HalsynFormat.distance(meters: $0, unit: unitSystem) } ?? "—")
                            .font(.system(size: 52, weight: .light).monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                        Text(verbatim: unitSystem.distanceUnitSymbol)
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Text(workout.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }

            LazyVGrid(columns: columns, spacing: HalsynSpacing.s) {
                HalsynMetricTile(title: "Tiempo", systemImage: "stopwatch", value: HalsynFormat.duration(workout.duration), unit: "")
                HalsynMetricTile(title: "Ritmo medio", systemImage: "speedometer", value: workout.averagePace?.formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                HalsynMetricTile(title: "FC media", systemImage: "heart", value: workout.averageHeartRate.map { String(Int($0)) }, unit: "lpm", status: workout.averageHeartRate == nil ? "No medida" : nil)
                HalsynMetricTile(title: "FC máx. registrada", systemImage: "heart.fill", value: workout.maxHeartRate.map { String(Int($0)) }, unit: "lpm", status: workout.maxHeartRate == nil ? "No medida" : nil)
                HalsynMetricTile(title: "Cadencia", systemImage: "metronome", value: workout.averageCadence.map { String(Int($0)) }, unit: "ppm", status: workout.averageCadence == nil ? "No medida" : nil)
                HalsynMetricTile(title: "Energía activa", systemImage: "flame", value: workout.activeEnergyKilocalories.map { String(Int($0)) }, unit: "kcal")
            }

            HalsynCard {
                HStack {
                    Text("Ruta, parciales, vueltas, zonas cardíacas y comparación histórica")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                    Spacer()
                    PhaseTag(phase: 5)
                }
            }

            DataOriginFootnote(origin: workout.origin)
        }
        .navigationTitle(Text(LocalizedStringKey(workout.activity.title)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Vista previa de una pantalla de entrenamiento con forma de Apple Watch.
/// Muestra valores de ejemplo (`DemoWorkoutSample`), nunca datos reales.
struct WatchScreenPreview: View {
    let profile: WorkoutScreenProfile
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric

    var body: some View {
        let sample = DemoWorkoutSample()
        HalsynWorkoutScreen(profile: profile) { sample.value(for: $0, unit: unitSystem) }
            .padding(12)
            .aspectRatio(0.82, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color(HalsynPalette.darkSurface), lineWidth: 6)
            )
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Vista previa del perfil \(profile.name) con valores de ejemplo"))
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(workout: WorkoutSummary(activity: .outdoorRun, start: .now, duration: 1476, distanceMeters: 5210, averageHeartRate: 148, maxHeartRate: 167, activeEnergyKilocalories: 354, averageCadence: 172, origin: .demo))
    }
}
