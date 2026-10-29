import CoreLocation
import Foundation

/// Historial corto de los permisos en el reloj: cuándo se pidieron y qué quedó,
/// con la versión de la app. Sirve para entender por qué se vuelve a preguntar.
enum PermissionLog {
    struct Entry: Codable, Hashable, Identifiable {
        let date: Date
        let build: String
        let text: String

        var id: String { "\(date.timeIntervalSince1970)-\(text)" }
    }

    static let key = "halsyn.watch.permissionLog"
    static let limit = 12

    static var entries: [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    static func add(_ text: String.LocalizationValue) {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let entry = Entry(date: .now, build: build, text: String(localized: text))
        let updated = Array((entries + [entry]).suffix(limit))
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// "al usar la app", "no permitida"…
    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedWhenInUse: String(localized: "al usar la app")
        case .authorizedAlways: String(localized: "siempre")
        case .denied: String(localized: "no permitida")
        case .restricted: String(localized: "restringida")
        case .notDetermined: String(localized: "sin decidir")
        @unknown default: String(localized: "sin decidir")
        }
    }
}
