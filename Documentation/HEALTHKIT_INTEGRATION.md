# Integración con HealthKit

## Estado actual (Fase 1)

- Entitlement `com.apple.developer.healthkit` en ambos targets y textos `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` en español.
- `HalsynHealthKit/HealthKitTypeCatalog.swift`: correspondencia `MetricKind` → tipo público de HealthKit y unidad de lectura.
- `HealthKitAvailability.isHealthDataAvailable` (llamada real a `HKHealthStore.isHealthDataAvailable()`), visible en Perfil.
- **No se pide autorización ni se leen datos todavía.** Toda la UI usa `DemoHealthDataProvider`.

## Correspondencia de métricas

| MetricKind | Tipo HealthKit | Unidad | Agregación diaria |
|---|---|---|---|
| heartRate | `.heartRate` | count/min | media |
| restingHeartRate | `.restingHeartRate` | count/min | último |
| heartRateVariability | `.heartRateVariabilitySDNN` | ms | media |
| respiratoryRate | `.respiratoryRate` | count/min | media |
| vo2Max | `.vo2Max` | ml/kg·min | último |
| oxygenSaturation | `.oxygenSaturation` | % | media |
| steps | `.stepCount` | count | suma |
| walkingRunningDistance | `.distanceWalkingRunning` | m | suma |
| activeEnergy | `.activeEnergyBurned` | kcal | suma |
| exerciseTime | `.appleExerciseTime` | min | suma |
| sleepDuration | `HKCategoryType(.sleepAnalysis)` | — (intervalos) | suma de fases "dormido" |

Running (lectura): `.runningSpeed`, `.runningPower`, `.runningStrideLength`, `.runningVerticalOscillation`, `.runningGroundContactTime`, rutas (`HKSeriesType.workoutRoute()`), entrenamientos.
Escritura: entrenamientos, rutas, energía activa y distancia.

## Plan Fase 2

1. `HealthKitDataProvider: HealthDataProviding` con `HKHealthStore` inyectable mediante protocolo (para mocks).
2. Autorización granular y explicada en onboarding; pedir solo los tipos del módulo que el usuario activa.
3. Consultas: `HKStatisticsCollectionQuery` (sumas/medias diarias, deduplicación de fuentes por HealthKit), `HKSampleQuery` (últimos valores), `HKAnchoredObjectQuery` (incrementales), `HKObserverQuery` cuando aporte valor.
4. Sueño: sumar intervalos `asleepCore/Deep/REM/Unspecified` con fusión de solapes entre fuentes.
5. Estados: HealthKit **no revela** si se denegó la lectura de un tipo. Se mostrará `noData` con una sugerencia de revisar permisos en Ajustes › Salud, sin afirmar que se denegó. `notAuthorized` solo cuando se pueda saber (p. ej. estado de escritura).
6. Fuente del dato (`HKSource`) propagada a `DataOrigin.healthKit(sourceName:)`.

## Pendiente de verificar (no asumir)

- Disponibilidad de cada tipo por modelo de Apple Watch y versión de watchOS.
- Qué métricas de running se entregan en vivo durante `HKLiveWorkoutBuilder` y cuáles solo al finalizar → `RUNNING_ENGINE.md`.
- Comportamiento de la firma con HealthKit en cuentas de desarrollador gratuitas.
