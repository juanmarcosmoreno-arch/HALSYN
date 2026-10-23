import Foundation
import UserNotifications

/// Notificación local diaria del resumen nocturno.
///
/// El contenido es genérico ("tu resumen está listo"): el resumen se calcula
/// al abrir la app con los datos de ese momento, sin procesar datos de salud en
/// segundo plano ni incluirlos en la notificación (privacidad en la pantalla
/// bloqueada).
enum NightlySummaryNotifications {
    static let identifier = "halsyn.nightlySummary"
    static let routeKey = "route"
    static let routeValue = "dailySummary"

    /// Pide permiso si hace falta y programa la notificación diaria.
    /// Devuelve `false` si el usuario no permite notificaciones.
    static func schedule(minutesAfterMidnight minutes: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "HÅLSYN"
        content.body = String(localized: "Tu resumen del día está listo.")
        content.userInfo = [routeKey: routeValue]

        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Recibe la pulsación en la notificación y abre el resumen.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    @MainActor var onOpenDailySummary: (@MainActor () -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo[NightlySummaryNotifications.routeKey] as? String
        guard route == NightlySummaryNotifications.routeValue else { return }
        await MainActor.run {
            onOpenDailySummary?()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
