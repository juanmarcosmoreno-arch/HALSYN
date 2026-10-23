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
    /// Ruta y FC de un entrenamiento (vacíos si no existen).
    func workoutDetail(for workout: WorkoutSummary) async -> WorkoutDetailData
    /// Puntuación diaria (`HealthScoreEngine`) si hay datos suficientes.
    func dailyScore(on day: Date) async -> DailyScore?
    /// Puntuaciones de los últimos `days` días que terminan en `endingOn`.
    /// Solo incluye los días con puntuación.
    func dailyScores(endingOn end: Date, days: Int) async -> [DailyScore]
    /// Recuperación estimada (0–100) de `RecoveryEngine`, si hay datos suficientes.
    func recoveryScore(on day: Date) async -> DailyScore?
    /// Recuperación con desglose de los `days` días que terminan en `end`.
    func recoveryEstimates(endingOn end: Date, days: Int) async -> [RecoveryEstimate]
    /// Noches con sueño registrado de los `days` días que terminan en `end`.
    func sleepNights(endingOn end: Date, days: Int) async -> [SleepNight]
    func goals() async -> [Goal]
    /// Emite cuando cambian los datos de origen (para refrescar la interfaz).
    func changes() -> AsyncStream<Void>
}

extension HealthDataProviding {
    public func workoutDetail(for workout: WorkoutSummary) async -> WorkoutDetailData {
        .empty(workout.origin)
    }

    public func recoveryEstimates(endingOn end: Date, days: Int) async -> [RecoveryEstimate] { [] }

    public func sleepNights(endingOn end: Date, days: Int) async -> [SleepNight] { [] }
}
