import HalsynCore
import HalsynDesign
import SwiftUI

/// SPRING en el reloj. Fase 1: selección de tipo de carrera y vista previa de
/// la pantalla de entrenamiento con valores de ejemplo. La sesión real
/// (HKWorkoutSession + HKLiveWorkoutBuilder + GPS) se implementa en la Fase 4.
struct WatchSpringView: View {
    var body: some View {
        List {
            NavigationLink {
                WatchWorkoutPreview(profile: .easyRun)
            } label: {
                Label("Carrera libre", systemImage: "figure.run")
            }
            NavigationLink {
                WatchWorkoutPreview(profile: .intervals)
            } label: {
                Label("Intervalos", systemImage: "repeat")
            }
            NavigationLink {
                WatchWorkoutPreview(profile: .race)
            } label: {
                Label("Competición", systemImage: "flag.checkered")
            }
            Text("El registro de entrenamientos llega en la Fase 4.")
                .font(.footnote)
                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                .listRowBackground(Color.clear)
        }
        .navigationTitle(Text(verbatim: HalsynModule.spring.brandName))
    }
}

/// Vista previa de la pantalla de entrenamiento. No inicia ninguna sesión ni
/// guarda nada en Apple Health.
struct WatchWorkoutPreview: View {
    let profile: WorkoutScreenProfile
    private let sample = DemoWorkoutSample()

    var body: some View {
        HalsynWorkoutScreen(profile: profile) { sample.value(for: $0) }
            .padding(.horizontal, 4)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(Text(verbatim: profile.name))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("DEMO")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(HalsynPalette.cautionDark))
                        .accessibilityLabel(Text("Vista previa con valores de ejemplo"))
                }
            }
    }
}

#Preview {
    NavigationStack { WatchSpringView() }
}
