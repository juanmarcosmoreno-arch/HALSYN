import Foundation
import HalsynCore
import UIKit

/// Copia en iCloud de lo que solo vive en este iPhone: plan, resultados de
/// tests, zapatillas (con fotos reducidas), mediciones de recuperación, ajustes
/// de carrera, metas, diario y perfil. Usa el almacén clave-valor de iCloud
/// (hasta 1 MB): los entrenamientos, el sueño y el pulso ya están en Salud.
///
/// - Al abrir la app se restaura solo lo que falta en el iPhone (iPhone nuevo
///   o app reinstalada); nunca pisa datos que ya están.
/// - Al salir de la app se actualiza la copia.
/// - Desde Perfil se puede restaurar todo a mano (pisa lo local).
@MainActor
enum CloudBackup {
    /// Claves de `UserDefaults` que se copian (datos del usuario, no cachés).
    static let keys: [String] = [
        "halsyn.trainingPlan",
        "halsyn.performanceResults",
        ComplaintStore.key,
        WorkoutQualityStore.excludedKey,
        WorkoutQualityStore.includedKey,
        GoalProbabilityHistory.key,
        ShoeStorage.key,
        RecoveryHistoryStore.key,
        RunSettings.storageKey,
        HabitJournalStorage.key,
        GoalStorage.key,
        "halsyn.cardio.inputs",
        ProfileDefaults.birthDateKey,
        "halsyn.profile.sex",
        "halsyn.profile.heightCm",
        "halsyn.profile.name",
        "halsyn.unitSystem",
        "halsyn.vila.sleepTarget",
        "halsyn.focusAreas",
        HalsynTheme.storageKey,
    ]
    static let dateKey = "halsyn.backup.date"
    static let photoPrefix = "halsyn.backup.shoePhoto."
    /// Ningún valor por encima de esto (el total del almacén es 1 MB).
    static let maximumValueSize = 300_000
    /// Mediciones de recuperación en la copia (la curva solo de la última).
    static let recoveryLimit = 200
    static let photoSide: CGFloat = 320

    private static var cloud: NSUbiquitousKeyValueStore { .default }
    private static var defaults: UserDefaults { .standard }

    /// iCloud con sesión iniciada en este iPhone.
    static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    static var lastBackup: Date? { cloud.object(forKey: dateKey) as? Date }

    // MARK: Restaurar

    /// Lo que falta en el iPhone y está en iCloud. Devuelve cuántos datos restauró.
    @discardableResult
    static func restoreMissing() -> Int {
        guard isAvailable else { return 0 }
        cloud.synchronize()
        var restored = 0
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = cloud.object(forKey: key) {
                defaults.set(value, forKey: key)
                restored += 1
            }
        }
        restored += restorePhotos(overwrite: false)
        return restored
    }

    /// Todo lo que hay en iCloud, aunque pise lo de este iPhone.
    @discardableResult
    static func restoreAll() -> Int {
        guard isAvailable else { return 0 }
        cloud.synchronize()
        var restored = 0
        for key in keys {
            if let value = cloud.object(forKey: key) {
                defaults.set(value, forKey: key)
                restored += 1
            }
        }
        restored += restorePhotos(overwrite: true)
        return restored
    }

    // MARK: Copiar

    /// Actualiza la copia (solo lo que cambió).
    static func backUp() {
        guard isAvailable else { return }
        for key in keys {
            guard var value = defaults.object(forKey: key) else {
                cloud.removeObject(forKey: key)
                continue
            }
            if key == RecoveryHistoryStore.key, let data = value as? Data {
                value = trimmedRecoveries(data) ?? data
            }
            if let data = value as? Data, data.count > maximumValueSize { continue }
            if !isEqual(cloud.object(forKey: key), value) {
                cloud.set(value, forKey: key)
            }
        }
        backUpPhotos()
        cloud.set(Date.now, forKey: dateKey)
        cloud.synchronize()
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        guard let lhs = lhs as? NSObject, let rhs = rhs as? NSObject else { return false }
        return lhs.isEqual(rhs)
    }

    /// Las últimas mediciones, con la curva solo en la última (el resto ocupa mucho).
    private static func trimmedRecoveries(_ data: Data) -> Data? {
        guard let results = try? RecoveryHistoryStore.decode(data) else { return nil }
        let recent = Array(results.suffix(recoveryLimit))
        let trimmed = recent.enumerated().map { index, result in
            index == recent.count - 1 ? result : HeartRateRecoveryResult(
                date: result.date, endHeartRate: result.endHeartRate,
                oneMinute: result.oneMinute, twoMinutes: result.twoMinutes, fiveMinutes: result.fiveMinutes,
                samples: []
            )
        }
        return try? RecoveryHistoryStore.encode(trimmed)
    }

    // MARK: Fotos de zapatillas

    private static var photoDirectory: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("shoes", isDirectory: true)
    }

    private static func backUpPhotos() {
        guard let directory = photoDirectory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var kept: Set<String> = []
        for file in files where file.pathExtension == "png" {
            let key = photoPrefix + file.deletingPathExtension().lastPathComponent
            kept.insert(key)
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let stored = cloud.dictionary(forKey: key), let date = stored["date"] as? Date, date >= modified { continue }
            guard let image = UIImage(contentsOfFile: file.path), let png = reduced(image)?.pngData() else { continue }
            cloud.set(["date": modified, "png": png], forKey: key)
        }
        // Fotos de zapatillas borradas.
        for key in cloud.dictionaryRepresentation.keys where key.hasPrefix(photoPrefix) && !kept.contains(key) {
            cloud.removeObject(forKey: key)
        }
    }

    private static func restorePhotos(overwrite: Bool) -> Int {
        guard let directory = photoDirectory else { return 0 }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var restored = 0
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(photoPrefix) {
            guard let stored = value as? [String: Any], let png = stored["png"] as? Data else { continue }
            let name = String(key.dropFirst(photoPrefix.count))
            let file = directory.appendingPathComponent(name).appendingPathExtension("png")
            guard overwrite || !FileManager.default.fileExists(atPath: file.path) else { continue }
            if (try? png.write(to: file, options: .atomic)) != nil { restored += 1 }
        }
        return restored
    }

    private static func reduced(_ image: UIImage) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, photoSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
