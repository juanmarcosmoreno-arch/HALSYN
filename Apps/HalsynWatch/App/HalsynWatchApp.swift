import HalsynCore
import HalsynDesign
import SwiftUI

@main
struct HalsynWatchApp: App {
    /// Fase 1: datos demo. En la Fase 2 el reloj leerá HealthKit directamente,
    /// sin depender del iPhone.
    private let provider: any HealthDataProviding = DemoHealthDataProvider()

    var body: some Scene {
        WindowGroup {
            WatchHomeView(provider: provider)
                .tint(Color(HalsynPalette.darkAccent))
        }
    }
}
