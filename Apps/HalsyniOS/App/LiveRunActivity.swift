import ActivityKit
import HalsynCore
import HealthKit
import UserNotifications

/// Muestra en la pantalla bloqueada la carrera que se graba en el reloj.
///
/// El reloj refleja su sesión en el iPhone (`startMirroringToCompanionDevice`):
/// HealthKit abre HÅLSYN en segundo plano y le pasa la sesión, por la que
/// llegan los datos cada 5 s. iOS solo deja *empezar* una Live Activity con la
/// app en primer plano: si la carrera empieza con HÅLSYN abierto en el iPhone,
/// aparece sola; si no, llega un aviso y con tocarlo (o al abrir la app) se
/// muestra. Una vez creada, se actualiza en segundo plano hasta el final.
@MainActor
final class LiveRunActivity: NSObject {
    static let shared = LiveRunActivity()
    static let notificationID = "halsyn-live-run"

    private var session: HKWorkoutSession?
    private var activity: Activity<RunActivityAttributes>?
    private var latest: RunLiveUpdate?
    private var notified = false

    /// Llamar al arrancar la app: así se recibe la sesión aunque iOS abra la
    /// app en segundo plano.
    func install(healthStore: HKHealthStore) {
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in LiveRunActivity.shared.began(session) }
        }
    }

    /// La app pasó a primer plano: si hay una carrera sin Live Activity, se crea.
    func appBecameActive() {
        guard session != nil, activity == nil else { return }
        start()
    }

    private func began(_ session: HKWorkoutSession) {
        self.session = session
        session.delegate = self
        latest = nil
        notified = false
        // Una de una carrera anterior que quedó abierta.
        for old in Activity<RunActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        start()
    }

    private func start() {
        guard activity == nil, let session, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = latest ?? initialState(session)
        do {
            activity = try Activity.request(
                attributes: RunActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil)
            )
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        } catch {
            // En segundo plano iOS no deja empezarla: aviso para abrir la app.
            notifyToOpen()
        }
    }

    private func initialState(_ session: HKWorkoutSession) -> RunLiveUpdate {
        let configuration = session.workoutConfiguration
        let kind: RunLiveUpdate.Activity = configuration.activityType == .cycling ? .ride : (configuration.activityType == .walking ? .walk : .run)
        let start = session.startDate ?? .now
        let metric = (UserDefaults.standard.string(forKey: AppPreferences.unitSystemKey) ?? UnitSystem.metric.rawValue) == UnitSystem.metric.rawValue
        return RunLiveUpdate(activity: kind, elapsed: max(0, Date.now.timeIntervalSince(start)), isPaused: false, distance: 0, metric: metric)
    }

    private func notifyToOpen() {
        guard !notified else { return }
        notified = true
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Carrera en curso")
        content.body = String(localized: "Toca para verla en la pantalla bloqueada mientras corres.")
        content.sound = nil
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    fileprivate func received(_ update: RunLiveUpdate) {
        latest = update
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: update, staleDate: Date.now.addingTimeInterval(60))) }
    }

    fileprivate func finished() {
        session = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        guard let activity else { return }
        self.activity = nil
        var final = latest
        final?.isPaused = true
        let content = final.map { ActivityContent(state: $0, staleDate: nil) }
        // El resumen queda unos minutos en la pantalla bloqueada.
        Task { await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(10 * 60))) }
    }
}

extension LiveRunActivity: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in LiveRunActivity.shared.finished() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        guard let last = data.last, let update = try? JSONDecoder().decode(RunLiveUpdate.self, from: last) else { return }
        Task { @MainActor in LiveRunActivity.shared.received(update) }
    }

    /// Reloj y iPhone se alejaron: la tarjeta queda con el último dato (pasa a
    /// «desactualizada» al minuto) y se pone al día si se vuelven a conectar.
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {}
}
