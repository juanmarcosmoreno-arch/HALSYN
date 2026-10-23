import Foundation

/// Errores del almacén de salud, independientes de HealthKit.
public enum HealthStoreError: Error, Equatable, Sendable {
    /// HealthKit no existe en este dispositivo.
    case unavailable
    /// Los datos están cifrados porque el dispositivo está bloqueado.
    case databaseLocked
    /// El usuario denegó el acceso (HealthKit solo lo revela para escritura).
    case notAuthorized
    case failed(String)
}

/// Acceso mínimo al almacén de salud que necesita HÅLSYN.
///
/// Solo usa tipos de HalsynCore, de modo que toda la lógica que hay encima
/// (`LiveHealthDataProvider`) se prueba con mocks sin HealthKit. La
/// implementación real es `HKHealthStoreClient` (módulo HalsynHealthKit).
public protocol HealthStoreClient: Sendable {
    var isHealthDataAvailable: Bool { get }

    /// `true` si todavía hay que mostrar la hoja de permisos de HealthKit.
    func shouldRequestAuthorization() async throws -> Bool
    /// Pide acceso de lectura a los tipos que usa HÅLSYN.
    func requestAuthorization() async throws

    /// Valores diarios agregados por el almacén (que ya elimina duplicados entre
    /// fuentes). Solo incluye los días con muestras: nunca rellena con ceros.
    /// Valores en la unidad base de `MetricKind.unit` (SpO₂ como fracción 0–1).
    func dailyStatistics(_ kind: MetricKind, aggregation: DailyAggregation, interval: DateInterval, calendar: Calendar) async throws -> [DailyValue]

    /// Muestra más reciente dentro del intervalo.
    func mostRecentSample(_ kind: MetricKind, in interval: DateInterval) async throws -> MetricReading?

    func sleepSamples(in interval: DateInterval) async throws -> [SleepSample]

    /// Entrenamientos de carrera más recientes, del más nuevo al más antiguo.
    func runningWorkouts(limit: Int) async throws -> [WorkoutSummary]

    /// Puntos de la ruta de un entrenamiento (vacío en cinta o sin GPS).
    func workoutRoute(workoutID: UUID) async throws -> [LocationSample]

    /// Lecturas de FC en el intervalo, en orden cronológico.
    func heartRateSamples(in interval: DateInterval) async throws -> [HeartRatePoint]

    /// Emite cada vez que cambian datos relevantes en el almacén.
    func changes() -> AsyncStream<Void>
}

extension HealthStoreClient {
    public func workoutRoute(workoutID: UUID) async throws -> [LocationSample] { [] }
    public func heartRateSamples(in interval: DateInterval) async throws -> [HeartRatePoint] { [] }
}
