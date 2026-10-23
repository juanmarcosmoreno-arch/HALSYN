import HalsynCore
import HalsynDesign
import SwiftUI

@main
struct HalsynWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var model = WatchModel()
    @State private var workout = WorkoutManager.shared
    /// Recibe del iPhone pantallas, zonas, alertas e intervalos.
    @State private var runSettings = RunSettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
                .environment(workout)
                .tint(Color(HalsynPalette.darkAccent))
                .task { model.start() }
                // Durante una carrera (o al iniciarla desde el iPhone) se muestra la sesión.
                .fullScreenCover(isPresented: Binding(
                    get: { workout.phase != .idle || workout.outcome != nil },
                    // Si el sistema cierra la hoja con el resumen a la vista, se descarta el resumen.
                    set: { presented in
                        if !presented && !workout.isActive { workout.dismissSummary() }
                    }
                )) {
                    WorkoutSessionView()
                        .environment(workout)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh()
            }
        }
    }
}
