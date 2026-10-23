import Foundation
import HalsynCore
import Observation
import WatchConnectivity

/// Ajustes de SPRING compartidos entre iPhone y Apple Watch.
///
/// - En el iPhone se editan; cada cambio se guarda y se envía al reloj con
///   `updateApplicationContext` (el sistema entrega solo la última versión,
///   aunque el reloj esté lejos o apagado).
/// - En el reloj se reciben y se guardan, así una carrera sin iPhone usa la
///   última configuración conocida.
/// - Nunca se envían datos de salud: solo preferencias (pantallas, zonas, alertas, intervalos).
@MainActor
@Observable
final class RunSettingsStore: NSObject {
    static let shared = RunSettingsStore()

    private(set) var settings: RunSettings
    /// Estado del enlace con el otro dispositivo (para mostrarlo en Ajustes).
    private(set) var link: LinkState = .unknown

    enum LinkState: Equatable {
        case unknown
        case unsupported
        case noWatch
        case appNotInstalled
        case ready
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: WCSession?

    init(defaults: UserDefaults = .standard, connect: Bool = true) {
        self.defaults = defaults
        settings = RunSettings.load(from: defaults)
        session = connect && WCSession.isSupported() ? WCSession.default : nil
        super.init()
        if let session {
            session.delegate = self
            session.activate()
        } else {
            link = .unsupported
        }
    }

    /// Modifica los ajustes, los guarda y los envía al reloj.
    func update(_ change: (inout RunSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        copy.modifiedAt = Date()
        settings = copy
        settings.save(to: defaults)
        send()
    }

    private func send() {
        guard let session, session.activationState == .activated, let data = try? settings.encoded() else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        try? session.updateApplicationContext([RunSettings.contextKey: data])
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context[RunSettings.contextKey] as? Data,
              let incoming = try? RunSettings.decoded(from: data),
              incoming.modifiedAt > settings.modifiedAt else { return }
        settings = incoming
        settings.save(to: defaults)
    }

    private func refreshLink() {
        guard let session else {
            link = .unsupported
            return
        }
        #if os(iOS)
        if !session.isPaired {
            link = .noWatch
        } else if !session.isWatchAppInstalled {
            link = .appNotInstalled
        } else {
            link = session.activationState == .activated ? .ready : .unknown
        }
        #else
        link = session.activationState == .activated ? .ready : .unknown
        #endif
    }

    fileprivate func activated() {
        refreshLink()
        if let session {
            receive(session.receivedApplicationContext)
        }
        #if os(iOS)
        // Por si el reloj se instaló después del último cambio.
        send()
        #endif
    }

    fileprivate func stateChanged() {
        refreshLink()
        #if os(iOS)
        send()
        #endif
    }

    fileprivate func received(_ data: Data) {
        receive([RunSettings.contextKey: data])
    }
}

extension RunSettingsStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[RunSettings.contextKey] as? Data else { return }
        Task { @MainActor in self.received(data) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Cambio de reloj: se reactiva para el nuevo.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.stateChanged() }
    }
    #endif
}
