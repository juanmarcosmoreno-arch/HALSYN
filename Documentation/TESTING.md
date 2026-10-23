# Pruebas

## Suites

| Suite | Framework | Dónde | Cubre |
|---|---|---|---|
| `Packages/HalsynKit/Tests/HalsynCoreTests` | Swift Testing | `swift test` (Linux/macOS) y ⌘U en Xcode | Marca, contraste WCAG de tokens, ritmo y formatos, disponibilidad de datos, `MetricDisplay`, proveedor demo (determinismo, rangos, etiquetado), perfiles de pantalla, generador determinista |
| `Tests/HalsyniOSTests` | XCTest | ⌘U en el esquema Halsyn | `AppModel`, carga de `HalsaSnapshot`, cambio relativo de INSIKT |

## Fixtures

- `DemoHealthDataProvider(seed:now:)`: datos sintéticos **deterministas** — mismo día y semilla ⇒ mismo valor, independientemente del orden de las consultas. Los tests fijan `now` para no depender del reloj.
- `SeededRandomNumberGenerator` (SplitMix64) para cualquier fixture aleatoria.
- Nunca se usan datos personales reales.

## Resultados verificados

Fase 1, ejecutado en Linux (Swift 6.3.1, x86_64): **`swift test` → 32 tests en 8 suites, todos superados** (incluye formato numérico por región).

Lo que **no** se ha podido ejecutar en el entorno de desarrollo (Linux, sin Xcode):

- Compilación de los targets iOS y watchOS, del design system SwiftUI y de `HalsynHealthKit`.
- `HalsyniOSTests`.

Ambas cosas las ejecuta el job `apple` de `.github/workflows/ci.yml` en un runner macOS; consulta su resultado antes de dar por buena una fase.

## Pendiente por fase

- Fase 2: mocks de `HKHealthStore` y tests de mapeo de consultas, permisos y duplicados.
- Fase 4: máquina de estados de sesión, `PaceEstimator` con trazas GPS sintéticas (ruido, pérdida de señal, pausas), distancia acumulada.
- Fase 5: zonas cardíacas, vueltas, intervalos.
- Fases 3, 6, 8: `HealthScoreEngine`, `RecoveryEngine`, `ReferencePercentileEngine`, `TrainingLoadEngine`.
- UI tests de navegación y snapshots de modo claro/oscuro.
