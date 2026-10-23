import HalsynCore
import Observation
import SwiftUI

/// Pestañas principales del iPhone. VILA y MÅL se abren desde HÄLSA e INSIKT.
enum AppTab: Hashable {
    case halsa
    case spring
    case insikt
    case profile
}

/// Estado compartido de la app. La fuente de datos se inyecta para poder
/// sustituir el modo demo por HealthKit (Fase 2) o por mocks en tests.
@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .halsa
    private(set) var provider: any HealthDataProviding

    init(provider: any HealthDataProviding = DemoHealthDataProvider()) {
        self.provider = provider
    }

    var dataMode: DataMode { provider.mode }
    var isDemo: Bool { provider.mode == .demo }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppPreferences {
    static let appearanceKey = "halsyn.appearance"
    static let unitSystemKey = "halsyn.unitSystem"
}
