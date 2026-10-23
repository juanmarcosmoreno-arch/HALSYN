import Foundation
import HalsynCore
import HalsynHealthKit
import Observation
import SwiftUI

/// Pestañas principales del iPhone. VILA y MÅL se abren desde HÄLSA e INSIKT.
enum AppTab: Hashable {
    case halsa
    case spring
    case insikt
    case profile
}

/// Estado compartido de la app: fuente de datos activa (demo o Apple Health),
/// estado de autorización y un token que cambia cuando hay que recargar datos.
@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .halsa
    /// Se activa al abrir la notificación del resumen nocturno.
    var isShowingDailySummary = false
    private(set) var provider: any HealthDataProviding
    private(set) var authorizationState: HealthAuthorizationState = .notRequired
    /// Las vistas lo incluyen en `.task(id:)`: al cambiar, recargan sus datos.
    private(set) var refreshToken = 0

    @ObservationIgnored private let makeProvider: (DataMode) -> any HealthDataProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// - Parameters:
    ///   - provider: proveedor fijo (tests y previews). Si es `nil`, se usa el
    ///     modo guardado por el usuario (demo por defecto).
    init(
        provider: (any HealthDataProviding)? = nil,
        defaults: UserDefaults = .standard,
        makeProvider: @escaping (DataMode) -> any HealthDataProviding = HealthDataProviderFactory.make
    ) {
        self.defaults = defaults
        self.makeProvider = makeProvider
        if let provider {
            self.provider = provider
        } else {
            let saved = defaults.string(forKey: AppPreferences.dataModeKey).flatMap(DataMode.init(rawValue:)) ?? .demo
            self.provider = makeProvider(saved)
        }
    }

    /// Clave para `.task(id:)`: cambia con la fuente de datos y con cada recarga.
    var reloadKey: String { "\(provider.mode.rawValue)-\(refreshToken)" }

    var dataMode: DataMode { provider.mode }
    var isDemo: Bool { provider.mode == .demo }

    /// Se llama al arrancar: lee el estado de permisos y empieza a escuchar cambios.
    func start() async {
        authorizationState = await provider.authorizationState()
        observeChanges()
    }

    /// Pide acceso a Apple Health y, si el usuario completa la hoja de permisos,
    /// pasa a datos reales. HealthKit no revela qué tipos se denegaron: la app
    /// mostrará "sin datos" en esos casos.
    @discardableResult
    func connectAppleHealth() async -> Bool {
        let live = makeProvider(.live)
        do {
            try await live.requestAuthorization()
        } catch {
            authorizationState = await live.authorizationState()
            return false
        }
        await activate(live)
        return true
    }

    func useDemoData() async {
        await activate(makeProvider(.demo))
    }

    /// Fuerza la recarga de las pantallas (vuelta a primer plano, "tirar para actualizar").
    func refresh() {
        refreshToken &+= 1
    }

    private func activate(_ newProvider: any HealthDataProviding) async {
        provider = newProvider
        defaults.set(newProvider.mode.rawValue, forKey: AppPreferences.dataModeKey)
        authorizationState = await newProvider.authorizationState()
        observeChanges()
        refresh()
    }

    private func observeChanges() {
        observation?.cancel()
        let stream = provider.changes()
        observation = Task { [weak self] in
            for await _ in stream {
                // Agrupa ráfagas de avisos (varias fuentes sincronizando a la vez).
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
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
    static let dataModeKey = "halsyn.dataMode"
    static let onboardingCompletedKey = "halsyn.onboardingCompleted"
    static let introKey = "halsyn.intro"
    static let sleepTargetKey = "halsyn.vila.sleepTarget"
    static let userNameKey = "halsyn.profile.name"
    static let focusAreasKey = "halsyn.focusAreas"
    static let nightlySummaryEnabledKey = "halsyn.nightlySummary.enabled"
    /// Minutos desde medianoche (por defecto, 21:30).
    static let nightlySummaryTimeKey = "halsyn.nightlySummary.minutes"
    static let defaultNightlySummaryMinutes = 21 * 60 + 30
}
