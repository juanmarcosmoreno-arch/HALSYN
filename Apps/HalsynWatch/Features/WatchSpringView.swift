import HalsynCore
import HalsynDesign
import SwiftUI

/// SPRING en el reloj: iniciar una carrera con un toque.
struct WatchSpringView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        List {
            Button {
                Task { await workout.start(indoor: false) }
            } label: {
                Label("Carrera al aire libre", systemImage: "figure.run")
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(HalsynPalette.darkPrimary)))

            Button {
                Task { await workout.start(indoor: true) }
            } label: {
                Label("Carrera en cinta", systemImage: "figure.run.treadmill")
            }

            Section {
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
            } footer: {
                Text("Intervalos y competición llegan en la Fase 5 (vista previa).")
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.spring.brandName))
    }
}

/// Vista previa de una pantalla de entrenamiento. No inicia ninguna sesión.
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
        .environment(WorkoutManager.shared)
}
