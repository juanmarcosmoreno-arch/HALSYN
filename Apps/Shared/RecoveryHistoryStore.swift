import Foundation
import HalsynCore
import Observation

/// Mediciones de recuperación del pulso que el usuario decidió guardar. Se
/// guardan en la app (no en Salud: la «Recuperación cardíaca» de Apple es una
/// estimación normalizada distinta y no se mezcla). El reloj las guarda y las
/// envía al iPhone, que es donde se ve la evolución.
@MainActor
@Observable
final class RecoveryHistoryStore {
    static let shared = RecoveryHistoryStore()
    static let key = "halsyn.recoveryHistory"
    static let limit = 300

    private(set) var results: [HeartRateRecoveryResult]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        results = defaults.data(forKey: Self.key).flatMap { try? Self.decode($0) } ?? []
    }

    /// Añade una medición (si ya existe una del mismo momento, la sustituye).
    func add(_ result: HeartRateRecoveryResult) {
        var updated = results.filter { abs($0.date.timeIntervalSince(result.date)) > 1 }
        updated.append(result)
        updated.sort { $0.date < $1.date }
        results = Array(updated.suffix(Self.limit))
        save()
    }

    func remove(_ result: HeartRateRecoveryResult) {
        results.removeAll { $0 == result }
        save()
    }

    private func save() {
        if let data = try? Self.encode(results) {
            defaults.set(data, forKey: Self.key)
        }
    }

    nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    nonisolated static func decode(_ data: Data) throws -> [HeartRateRecoveryResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([HeartRateRecoveryResult].self, from: data)
    }

    nonisolated static func decodeOne(_ data: Data) throws -> HeartRateRecoveryResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(HeartRateRecoveryResult.self, from: data)
    }
}
