import Foundation
import HalsynCore
import Observation
import WatchConnectivity
#if os(watchOS)
import WidgetKit
#endif

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
    /// Puntuación y recuperación calculadas en el iPhone (que tiene todo el
    /// historial de Salud). El reloj las muestra en lugar de calcular las suyas
    /// con menos datos, para que ambos digan lo mismo.
    private(set) var phoneSnapshot: WidgetSnapshot?

    static let snapshotContextKey = "dailySnapshot"
    private static let snapshotStorageKey = "halsyn.phoneSnapshot"

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
        phoneSnapshot = WidgetSnapshotStore.load(from: defaults, key: Self.snapshotStorageKey)
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

    /// iPhone: comparte con el reloj la puntuación y la recuperación de hoy.
    func shareDaily(_ snapshot: WidgetSnapshot) {
        guard snapshot != phoneSnapshot else { return }
        phoneSnapshot = snapshot
        WidgetSnapshotStore.save(snapshot, to: defaults, key: Self.snapshotStorageKey)
        send()
    }

    private func send() {
        guard let session, session.activationState == .activated, let data = try? settings.encoded() else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        // El contexto se reemplaza entero: viajan siempre los ajustes y el último resumen.
        var context: [String: Any] = [RunSettings.contextKey: data]
        if let snapshot = phoneSnapshot, let encoded = WidgetSnapshotStore.encode(snapshot) {
            context[Self.snapshotContextKey] = encoded
        }
        try? session.updateApplicationContext(context)
    }

    private func receive(_ context: [String: Any]) {
        if let data = context[Self.snapshotContextKey] as? Data, let snapshot = WidgetSnapshotStore.decode(data),
           snapshot.updatedAt > (phoneSnapshot?.updatedAt ?? .distantPast) {
            phoneSnapshot = snapshot
            WidgetSnapshotStore.save(snapshot, to: defaults, key: Self.snapshotStorageKey)
            #if os(watchOS)
            // Las complicaciones del reloj muestran lo mismo que el iPhone.
            if let shared = WidgetSnapshotStore.sharedDefaults() {
                WidgetSnapshotStore.save(snapshot, to: shared)
                WidgetCenter.shared.reloadAllTimelines()
            }
            #endif
        }
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

    fileprivate func received(_ context: [String: Data]) {
        receive(context)
    }
}

extension RunSettingsStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = applicationContext.compactMapValues { $0 as? Data }
        Task { @MainActor in self.received(context) }
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
