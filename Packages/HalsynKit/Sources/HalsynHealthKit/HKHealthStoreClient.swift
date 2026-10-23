#if canImport(HealthKit) && (os(iOS) || os(watchOS))
import CoreLocation
import Foundation
import HalsynCore
import HealthKit

/// Implementación de `HealthStoreClient` sobre `HKHealthStore`.
///
/// Capa fina: traduce consultas de HealthKit a tipos de HalsynCore. Toda la
/// semántica (ventanas, sueño, estados) vive en `LiveHealthDataProvider`.
/// - Las estadísticas usan `HKStatisticsCollectionQueryDescriptor`, que combina
///   las fuentes según la prioridad del usuario en Salud (sin duplicados).
/// - Solo se pide acceso de lectura. La escritura de entrenamientos se pedirá
///   en la Fase 4, cuando exista.
public final class HKHealthStoreClient: HealthStoreClient, @unchecked Sendable {
    // HKHealthStore es seguro entre hilos según la documentación de Apple.
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: Autorización

    public func shouldRequestAuthorization() async throws -> Bool {
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: HealthKitTypeCatalog.coreReadTypes)
            return status != .unnecessary
        } catch {
            throw Self.map(error)
        }
    }

    public func requestAuthorization() async throws {
        do {
            try await store.requestAuthorization(toShare: [], read: HealthKitTypeCatalog.coreReadTypes)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Consultas

    public func dailyStatistics(_ kind: MetricKind, aggregation: DailyAggregation, interval: DateInterval, calendar: Calendar) async throws -> [DailyValue] {
        guard let type = HealthKitTypeCatalog.objectType(for: kind) as? HKQuantityType,
              let unit = HealthKitTypeCatalog.unit(for: kind) else { return [] }
        let options: HKStatisticsOptions
        switch aggregation {
        case .sum: options = .cumulativeSum
        case .average: options = .discreteAverage
        case .latest: options = .mostRecent
        }
        var dayComponents = DateComponents()
        dayComponents.day = 1
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: Self.predicate(for: interval)),
            options: options,
            anchorDate: calendar.startOfDay(for: interval.start),
            intervalComponents: dayComponents
        )
        do {
            let collection = try await descriptor.result(for: store)
            var values: [DailyValue] = []
            for statistics in collection.statistics() {
                let quantity: HKQuantity?
                switch aggregation {
                case .sum: quantity = statistics.sumQuantity()
                case .average: quantity = statistics.averageQuantity()
                case .latest: quantity = statistics.mostRecentQuantity()
                }
                if let quantity {
                    values.append(DailyValue(day: statistics.startDate, value: quantity.doubleValue(for: unit)))
                }
            }
            return values
        } catch let error as HKError where error.code == .errorNoData {
            return []
        } catch {
            throw Self.map(error)
        }
    }

    public func mostRecentSample(_ kind: MetricKind, in interval: DateInterval) async throws -> MetricReading? {
        guard let type = HealthKitTypeCatalog.objectType(for: kind) as? HKQuantityType,
              let unit = HealthKitTypeCatalog.unit(for: kind) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.quantitySample(type: type, predicate: Self.predicate(for: interval))],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.endDate, order: .reverse)],
            limit: 1
        )
        do {
            guard let sample = try await descriptor.result(for: store).first else { return nil }
            return MetricReading(
                kind: kind,
                value: sample.quantity.doubleValue(for: unit),
                date: sample.endDate,
                origin: .healthKit(sourceName: sample.sourceRevision.source.name)
            )
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    public func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: Self.predicate(for: interval))],
            sortDescriptors: [SortDescriptor(\HKCategorySample.startDate)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            return samples.compactMap { sample in
                guard let stage = Self.sleepStage(sample.value) else { return nil }
                return SleepSample(start: sample.startDate, end: sample.endDate, stage: stage, sourceName: sample.sourceRevision.source.name)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        } catch {
            throw Self.map(error)
        }
    }

    public func runningWorkouts(limit: Int) async throws -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.workout(HKQuery.predicateForWorkouts(with: .running))],
            sortDescriptors: [SortDescriptor(\HKWorkout.endDate, order: .reverse)],
            limit: limit
        )
        do {
            return try await descriptor.result(for: store).map(Self.summary)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        } catch {
            throw Self.map(error)
        }
    }

    public func workoutRoute(workoutID: UUID) async throws -> [LocationSample] {
        do {
            let workouts = try await HKSampleQueryDescriptor(
                predicates: [HKSamplePredicate.workout(HKQuery.predicateForObject(with: workoutID))],
                sortDescriptors: [],
                limit: 1
            ).result(for: store)
            guard let workout = workouts.first else { return [] }
            let routes = try await routes(of: workout)
            var samples: [LocationSample] = []
            for route in routes {
                samples += try await locations(of: route).map(Self.sample)
            }
            return samples.sorted { $0.timestamp < $1.timestamp }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        } catch {
            throw Self.map(error)
        }
    }

    public func heartRateSamples(in interval: DateInterval) async throws -> [HeartRatePoint] {
        let beatsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate.quantitySample(type: HKQuantityType(.heartRate), predicate: Self.predicate(for: interval))],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)]
        )
        do {
            return try await descriptor.result(for: store).map {
                HeartRatePoint(date: $0.startDate, bpm: $0.quantity.doubleValue(for: beatsPerMinute))
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        } catch {
            throw Self.map(error)
        }
    }

    /// Rutas asociadas a un entrenamiento (normalmente una).
    private func routes(of workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let store = self.store
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? []).compactMap { $0 as? HKWorkoutRoute })
                }
            }
            store.execute(query)
        }
    }

    /// `HKWorkoutRouteQuery` entrega la ruta en lotes hasta `done`.
    private func locations(of route: HKWorkoutRoute) async throws -> [CLLocation] {
        let store = self.store
        let collector = RouteCollector()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                collector.handle(batch: batch, done: done, error: error, continuation: continuation)
            }
            store.execute(query)
        }
    }

    private static func sample(_ location: CLLocation) -> LocationSample {
        LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
            timestamp: location.timestamp
        )
    }

    // MARK: Cambios

    /// Una `HKObserverQuery` por tipo; emite cuando llegan datos nuevos.
    public func changes() -> AsyncStream<Void> {
        let store = self.store
        var types: [HKSampleType] = MetricKind.allCases.compactMap { HealthKitTypeCatalog.objectType(for: $0) as? HKSampleType }
        types.append(HKObjectType.workoutType())
        // Solo se guarda el último aviso pendiente: las ráfagas se agrupan.
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            var queries: [HKObserverQuery] = []
            for type in types {
                let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                    if error == nil {
                        continuation.yield()
                    }
                    completionHandler()
                }
                queries.append(query)
                store.execute(query)
            }
            let running = queries
            continuation.onTermination = { _ in
                for query in running {
                    store.stop(query)
                }
            }
        }
    }

    // MARK: Conversión

    private static func predicate(for interval: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
    }

    static func sleepStage(_ rawValue: Int) -> SleepSample.Stage? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return nil }
        switch value {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        @unknown default: return nil
        }
    }

    static func summary(_ workout: HKWorkout) -> WorkoutSummary {
        let beatsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        let isIndoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false
        return WorkoutSummary(
            id: workout.uuid,
            activity: isIndoor ? .indoorRun : .outdoorRun,
            start: workout.startDate,
            duration: workout.duration,
            distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: HKUnit.meter()),
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: beatsPerMinute),
            maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
            activeEnergyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()),
            // La cadencia media no se deriva todavía: se calculará en la Fase 4
            // con los datos del propio entrenamiento, no con una estimación.
            averageCadence: nil,
            origin: .healthKit(sourceName: workout.sourceRevision.source.name)
        )
    }

    static func map(_ error: Error) -> HealthStoreError {
        guard let error = error as? HKError else { return .failed(String(describing: error)) }
        switch error.code {
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: return .unavailable
        case .errorDatabaseInaccessible: return .databaseLocked
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined: return .notAuthorized
        default: return .failed(error.localizedDescription)
        }
    }
}

/// Acumula los lotes de `HKWorkoutRouteQuery` (llegan en serie desde HealthKit)
/// y reanuda la continuación una sola vez.
private final class RouteCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var locations: [CLLocation] = []
    private var finished = false

    func handle(batch: [CLLocation]?, done: Bool, error: Error?, continuation: CheckedContinuation<[CLLocation], Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if let error {
            finished = true
            continuation.resume(throwing: error)
            return
        }
        locations += batch ?? []
        if done {
            finished = true
            continuation.resume(returning: locations)
        }
    }
}
#endif
