import Foundation

/// Proveedor de datos reales (Apple Health) sobre un `HealthStoreClient`.
///
/// Aquí vive la semántica de HÅLSYN, independiente de HealthKit:
/// - Ventanas diarias en el calendario del usuario; el sueño se asigna a la
///   noche que termina ese día (`SleepAggregator`).
/// - Las métricas `.latest` buscan el último valor hacia atrás
///   (`MetricKind.latestLookbackDays`) y conservan la fecha real del dato.
/// - Ausencia de datos, bloqueo del dispositivo, errores y dispositivos sin
///   HealthKit se devuelven como estados distintos, nunca como valores.
/// - Puntuaciones y objetivos no se inventan: llegan con sus motores (Fases 3, 6 y 9).
public struct LiveHealthDataProvider: HealthDataProviding {
    public let mode: DataMode = .live
    private let client: any HealthStoreClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(client: any HealthStoreClient, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.calendar = calendar
        self.now = now
    }

    // MARK: Autorización

    public func authorizationState() async -> HealthAuthorizationState {
        guard client.isHealthDataAvailable else { return .unavailable }
        do {
            return try await client.shouldRequestAuthorization() ? .notDetermined : .requested
        } catch {
            return .notDetermined
        }
    }

    public func requestAuthorization() async throws {
        guard client.isHealthDataAvailable else { throw HealthStoreError.unavailable }
        try await client.requestAuthorization()
    }

    // MARK: Métricas

    public func latest(_ kind: MetricKind, on day: Date) async -> MetricAvailability {
        guard client.isHealthDataAvailable else { return .unsupported }
        let dayStart = calendar.startOfDay(for: day)
        guard dayStart <= calendar.startOfDay(for: now()),
              let dayInterval = calendar.dateInterval(of: .day, for: dayStart) else { return .noData }
        do {
            switch kind {
            case .sleepDuration:
                let window = SleepAggregator.nightWindow(endingOn: dayStart, calendar: calendar)
                let samples = try await client.sleepSamples(in: window)
                let seconds = SleepAggregator.asleepDuration(samples, in: window)
                guard seconds > 0 else { return .noData }
                let source = SleepAggregator.dominantSource(samples, in: window)
                return .available(MetricReading(kind: kind, value: seconds / 3600, date: dayStart, origin: .healthKit(sourceName: source)))

            case _ where kind.dailyAggregation == .latest:
                let lookbackStart = calendar.date(byAdding: .day, value: -(kind.latestLookbackDays - 1), to: dayStart) ?? dayStart
                let interval = DateInterval(start: lookbackStart, end: dayInterval.end)
                guard let reading = try await client.mostRecentSample(kind, in: interval) else { return .noData }
                return .available(reading)

            default:
                let values = try await client.dailyStatistics(kind, aggregation: kind.dailyAggregation, interval: dayInterval, calendar: calendar)
                guard let value = values.first(where: { calendar.isDate($0.day, inSameDayAs: dayStart) }) else { return .noData }
                return .available(MetricReading(kind: kind, value: value.value, date: dayStart, origin: .healthKit(sourceName: nil)))
            }
        } catch {
            return Self.availability(for: error)
        }
    }

    public func dailySeries(_ kind: MetricKind, days: Int, endingOn end: Date) async -> MetricSeries {
        let origin = DataOrigin.healthKit(sourceName: nil)
        guard client.isHealthDataAvailable, days > 0 else { return MetricSeries(kind: kind, values: [], origin: origin) }
        let lastDay = min(calendar.startOfDay(for: end), calendar.startOfDay(for: now()))
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1), to: lastDay),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
            return MetricSeries(kind: kind, values: [], origin: origin)
        }
        do {
            if kind == .sleepDuration {
                return MetricSeries(kind: kind, values: try await sleepSeries(from: firstDay, through: lastDay), origin: origin)
            }
            let values = try await client.dailyStatistics(kind, aggregation: kind.dailyAggregation, interval: DateInterval(start: firstDay, end: rangeEnd), calendar: calendar)
            let normalized = values
                .map { DailyValue(day: calendar.startOfDay(for: $0.day), value: $0.value) }
                .filter { $0.day >= firstDay && $0.day <= lastDay }
                .sorted { $0.day < $1.day }
            return MetricSeries(kind: kind, values: normalized, origin: origin)
        } catch {
            return MetricSeries(kind: kind, values: [], origin: origin)
        }
    }

    private func sleepSeries(from firstDay: Date, through lastDay: Date) async throws -> [DailyValue] {
        let fullWindow = DateInterval(
            start: SleepAggregator.nightWindow(endingOn: firstDay, calendar: calendar).start,
            end: SleepAggregator.nightWindow(endingOn: lastDay, calendar: calendar).end
        )
        let samples = try await client.sleepSamples(in: fullWindow)
        var values: [DailyValue] = []
        var day = firstDay
        while day <= lastDay {
            let seconds = SleepAggregator.asleepDuration(samples, in: SleepAggregator.nightWindow(endingOn: day, calendar: calendar))
            if seconds > 0 {
                values.append(DailyValue(day: day, value: seconds / 3600))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return values
    }

    // MARK: Entrenamientos, puntuaciones, objetivos

    public func recentWorkouts(limit: Int) async -> [WorkoutSummary] {
        guard client.isHealthDataAvailable else { return [] }
        return (try? await client.runningWorkouts(limit: limit)) ?? []
    }

    /// HealthScoreEngine llega en la Fase 3: sin motor no hay puntuación.
    public func dailyScore(on day: Date) async -> DailyScore? { nil }

    /// RecoveryEngine llega en la Fase 6.
    public func recoveryScore(on day: Date) async -> DailyScore? { nil }

    /// Los objetivos del usuario se crean en la Fase 9.
    public func goals() async -> [Goal] { [] }

    public func changes() -> AsyncStream<Void> {
        client.changes()
    }

    static func availability(for error: Error) -> MetricAvailability {
        switch error as? HealthStoreError {
        case .unavailable: .unsupported
        case .databaseLocked: .temporarilyUnavailable
        case .notAuthorized: .notAuthorized
        case .failed, nil: .readFailed
        }
    }
}
