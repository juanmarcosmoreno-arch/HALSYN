import Foundation
import HalsynCore
import HalsynHealthKit
import Observation

/// Estado de la app del reloj. El Apple Watch lee HealthKit por sí mismo
/// (funciona sin el iPhone); su almacén contiene un subconjunto reciente de los
/// datos de Salud, por lo que el historial largo se consulta en el iPhone.
@MainActor
@Observable
final class WatchModel {
    private(set) var provider: any HealthDataProviding
    private(set) var refreshToken = 0
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    static let dataModeKey = "halsyn.watch.dataMode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.dataModeKey).flatMap(DataMode.init(rawValue:)) ?? .demo
        provider = HealthDataProviderFactory.make(saved)
    }

    var isDemo: Bool { provider.mode == .demo }
    var reloadKey: String { "\(provider.mode.rawValue)-\(refreshToken)" }

    func start() {
        observeChanges()
    }

    /// Muestra la hoja de permisos de HealthKit en el reloj y pasa a datos reales.
    @discardableResult
    func connectAppleHealth() async -> Bool {
        let live = HealthDataProviderFactory.make(.live)
        do {
            try await live.requestAuthorization()
        } catch {
            return false
        }
        provider = live
        defaults.set(DataMode.live.rawValue, forKey: Self.dataModeKey)
        observeChanges()
        refresh()
        return true
    }

    func refresh() {
        refreshToken &+= 1
    }

    private func observeChanges() {
        observation?.cancel()
        let stream = provider.changes()
        observation = Task { [weak self] in
            for await _ in stream {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}
