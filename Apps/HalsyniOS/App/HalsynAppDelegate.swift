import HealthKit
import UIKit

/// Cuando el reloj pide permisos de Salud, watchOS a veces manda la confirmación
/// al iPhone. Sin esto la petición nunca se completa y el reloj vuelve a
/// preguntar en cada entrenamiento.
final class HalsynAppDelegate: NSObject, UIApplicationDelegate {
    private let healthStore = HKHealthStore()

    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        healthStore.handleAuthorizationForExtension { _, _ in }
    }
}
