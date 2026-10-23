import HealthKit
import WatchKit

/// Recibe del sistema el arranque de un entrenamiento desde el iPhone
/// (`HKHealthStore.startWatchApp`) y la recuperación tras un cierre inesperado.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WorkoutManager.shared.start(configuration: workoutConfiguration)
        }
    }

    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            await WorkoutManager.shared.recover()
        }
    }
}
