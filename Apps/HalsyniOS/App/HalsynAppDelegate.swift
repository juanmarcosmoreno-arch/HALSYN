import HealthKit
import UIKit

/// Cuando el reloj pide permisos de Salud, watchOS a veces manda la confirmación
/// al iPhone. Sin esto la petición nunca se completa y el reloj vuelve a
/// preguntar en cada entrenamiento.
final class HalsynAppDelegate: NSObject, UIApplicationDelegate {
    private let healthStore = HKHealthStore()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Informes de cuelgues y cierres (Perfil › Diagnóstico).
        MainActor.assumeIsolated { DiagnosticsStore.shared.start() }
        return true
    }

    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        healthStore.handleAuthorizationForExtension { _, _ in }
    }
}
