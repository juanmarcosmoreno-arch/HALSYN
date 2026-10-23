import Foundation

/// Modo de datos activo. La interfaz muestra siempre un distintivo en modo demo.
public enum DataMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case demo
    case live

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .demo: "Modo demo"
        case .live: "Apple Health"
        }
    }
}

/// Estado de autorización agregado para el conjunto de métricas de lectura.
///
/// HealthKit no revela si el usuario denegó la *lectura* de un tipo concreto
/// (por privacidad), así que el estado real solo distingue entre "ya se pidió"
/// y "aún no se pidió". `notAuthorized` en `MetricAvailability` se reserva para
/// los casos en los que sí se puede saber.
public enum HealthAuthorizationState: String, Sendable {
    case notDetermined
    case requested
    case unavailable
    /// El proveedor no necesita autorización (modo demo).
    case notRequired
}

/// Abstracción sobre la fuente de datos fisiológicos. Implementaciones:
/// - `DemoHealthDataProvider`: datos sintéticos reproducibles.
/// - `HealthKitDataProvider` (Fase 2, módulo HalsynHealthKit): Apple Health.
///
/// Las vistas y los motores dependen solo de este protocolo, lo que permite
/// probar con datos simulados.
public protocol HealthDataProviding: Sendable {
    var mode: DataMode { get }

    func authorizationState() async -> HealthAuthorizationState
    func requestAuthorization() async throws

    /// Último valor del día indicado (agregado según `MetricKind.dailyAggregation`).
    func latest(_ kind: MetricKind, on day: Date) async -> MetricAvailability
    /// Serie diaria de los últimos `days` días, terminando en `endingOn` (incluido).
    func dailySeries(_ kind: MetricKind, days: Int, endingOn: Date) async -> MetricSeries
    func recentWorkouts(limit: Int) async -> [WorkoutSummary]
    /// Puntuación diaria si existe. En Fase 1 solo la ofrece el modo demo.
    func dailyScore(on day: Date) async -> DailyScore?
    /// Recuperación estimada (0–100). El motor real llega en la Fase 6.
    func recoveryScore(on day: Date) async -> DailyScore?
    func goals() async -> [Goal]
}
