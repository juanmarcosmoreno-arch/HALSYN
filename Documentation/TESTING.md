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

GitHub Actions (commit `fa77845`, runner `macos-15`): **todos los jobs en verde**:

- `HalsynKit` en macOS: `swift build` + `swift test` (núcleo, design system y HealthKit).
- App de Apple Watch compilada para el simulador de watchOS.
- App de iPhone (con el reloj embebido) compilada y `HalsyniOSTests` + `HalsynCoreTests` ejecutados en un simulador de iPhone.
- Catálogos de idiomas sincronizados con el código.

Los dos primeros runs fallaron por errores de compilación reales (colisión de `RGBColor` con un tipo de macOS e inferencia genérica en Swift Charts), corregidos en ese commit. Nada se ha probado aún en dispositivos físicos.

## Pendiente por fase

- Fase 2: mocks de `HKHealthStore` y tests de mapeo de consultas, permisos y duplicados.
- Fase 4: máquina de estados de sesión, `PaceEstimator` con trazas GPS sintéticas (ruido, pérdida de señal, pausas), distancia acumulada.
- Fase 5: zonas cardíacas, vueltas, intervalos.
- Fases 3, 6, 8: `HealthScoreEngine`, `RecoveryEngine`, `ReferencePercentileEngine`, `TrainingLoadEngine`.
- UI tests de navegación y snapshots de modo claro/oscuro.
