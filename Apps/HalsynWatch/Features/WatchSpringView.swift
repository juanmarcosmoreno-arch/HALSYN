import HalsynCore
import HalsynDesign
import SwiftUI

/// SPRING en el reloj: iniciar una carrera con un toque. Los planes de
/// intervalos, pantallas, zonas y alertas se editan en el iPhone y llegan solos.
struct WatchSpringView: View {
    @Environment(WorkoutManager.self) private var workout
    private var settings: RunSettings { RunSettingsStore.shared.settings }

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
                ForEach(settings.intervalPlans) { plan in
                    Button {
                        Task { await workout.start(indoor: false, plan: plan) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(verbatim: plan.name)
                            } icon: {
                                Image(systemName: "repeat")
                            }
                            Text(verbatim: IntervalPlanFormatter.summary(plan, unit: settings.unitSystem))
                                .font(.caption2)
                                .foregroundStyle(Color(HalsynPalette.secondaryTextDark))
                        }
                    }
                }
            } header: {
                Text("Intervalos")
            } footer: {
                Text("Edita planes, pantallas, zonas y alertas en el iPhone: SPRING › Ajustes de carrera.")
            }

            Section {
                ForEach(settings.validScreens) { profile in
                    NavigationLink {
                        WatchWorkoutPreview(profile: profile)
                    } label: {
                        Label {
                            Text(verbatim: profile.name)
                        } icon: {
                            Image(systemName: "rectangle.grid.1x2")
                        }
                    }
                }
            } header: {
                Text("Pantallas")
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
        HalsynWorkoutScreen(profile: profile) { sample.value(for: $0, unit: RunSettingsStore.shared.settings.unitSystem) }
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
