#if canImport(HealthKit)
import HalsynCore
import HealthKit

/// Correspondencia entre las métricas de HÅLSYN y los tipos públicos de HealthKit.
///
/// Fase 1: solo catálogo y disponibilidad. Las consultas reales
/// (`HealthKitDataProvider`) se implementan en la Fase 2.
public enum HealthKitTypeCatalog {
    /// Tipo de HealthKit para cada métrica.
    public static func objectType(for kind: MetricKind) -> HKObjectType {
        switch kind {
        case .heartRate: return HKQuantityType(.heartRate)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .heartRateVariability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .vo2Max: return HKQuantityType(.vo2Max)
        case .oxygenSaturation: return HKQuantityType(.oxygenSaturation)
        case .steps: return HKQuantityType(.stepCount)
        case .walkingRunningDistance: return HKQuantityType(.distanceWalkingRunning)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .exerciseTime: return HKQuantityType(.appleExerciseTime)
        case .sleepDuration: return HKCategoryType(.sleepAnalysis)
        }
    }

    /// Unidad de HealthKit con la que se leen las cantidades. `nil` para categorías.
    public static func unit(for kind: MetricKind) -> HKUnit? {
        switch kind {
        case .heartRate, .restingHeartRate, .respiratoryRate: return HKUnit.count().unitDivided(by: HKUnit.minute())
        case .heartRateVariability: return HKUnit.secondUnit(with: .milli)
        case .vo2Max: return HKUnit(from: "ml/kg*min")
        case .oxygenSaturation: return HKUnit.percent()
        case .steps: return HKUnit.count()
        case .walkingRunningDistance: return HKUnit.meter()
        case .activeEnergy: return HKUnit.kilocalorie()
        case .exerciseTime: return HKUnit.minute()
        case .sleepDuration: return nil
        }
    }

    /// Conjunto mínimo de lectura para los módulos HÄLSA y VILA.
    /// Se pide de forma granular y con explicación previa (onboarding, Fase 2).
    public static var coreReadTypes: Set<HKObjectType> {
        var types = Set(MetricKind.allCases.map(objectType(for:)))
        types.insert(HKObjectType.workoutType())
        // Ruta de las carreras (mapa y parciales en el detalle, Fase 5).
        types.insert(HKSeriesType.workoutRoute())
        return types
    }

    /// Métricas de running con API pública. La disponibilidad en vivo frente a
    /// solo posterior al entrenamiento se documenta en `RUNNING_ENGINE.md` y se
    /// verificará en dispositivo físico en la Fase 4.
    public static var runningReadTypes: Set<HKObjectType> {
        [
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
    }

    /// Tipos que HÅLSYN escribirá (entrenamientos y rutas creados en el reloj).
    public static var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }
}

/// Información de disponibilidad de HealthKit en el dispositivo actual.
public enum HealthKitAvailability {
    /// `false` en iPad sin Health o en dispositivos sin HealthKit.
    public static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
}
#endif
