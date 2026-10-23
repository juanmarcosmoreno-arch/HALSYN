# Pruebas

## Suites

| Suite | Framework | Dónde | Cubre |
|---|---|---|---|
| `Packages/HalsynKit/Tests/HalsynCoreTests` | Swift Testing | `swift test` (Linux/macOS) y ⌘U en Xcode | Marca, contraste WCAG de tokens, ritmo y formatos, disponibilidad de datos, `MetricDisplay`, proveedor demo (determinismo, rangos, etiquetado), perfiles de pantalla, generador determinista |
| `Packages/HalsynKit/Tests/HalsynCoreTests/LiveHealthDataProviderTests.swift` | Swift Testing | igual | Proveedor real con `MockHealthStoreClient`: permisos, estados de error, sueño (fases, solapes, ventana), último valor y su fecha, series sin ceros, sin puntuaciones inventadas |
| `Tests/HalsyniOSTests` | XCTest | ⌘U en el esquema Halsyn | `AppModel` (conexión, persistencia de la fuente, vuelta a demo, fallo de conexión), `HalsaSnapshot` demo y real sin datos, INSIKT |

## Fixtures

- `DemoHealthDataProvider(seed:now:)`: datos sintéticos **deterministas** — mismo día y semilla ⇒ mismo valor, independientemente del orden de las consultas. Los tests fijan `now` para no depender del reloj.
- `SeededRandomNumberGenerator` (SplitMix64) para cualquier fixture aleatoria.
- Nunca se usan datos personales reales.

## Resultados verificados

Fase 1, ejecutado en Linux (Swift 6.3.1, x86_64): **`swift test` → 32 tests en 8 suites, todos superados** (incluye formato numérico por región). Fase 2: 48 tests en 10 suites.

GitHub Actions (commit `fa77845`, runner `macos-15`): **todos los jobs en verde**:

- `HalsynKit` en macOS: `swift build` + `swift test` (núcleo, design system y HealthKit).
- App de Apple Watch compilada para el simulador de watchOS.
- App de iPhone (con el reloj embebido) compilada y `HalsyniOSTests` + `HalsynCoreTests` ejecutados en un simulador de iPhone.
- Catálogos de idiomas sincronizados con el código.

Los dos primeros runs fallaron por errores de compilación reales (colisión de `RGBColor` con un tipo de macOS e inferencia genérica en Swift Charts), corregidos en ese commit. Nada se ha probado aún en dispositivos físicos.

Fase 2, GitHub Actions (commit `de15b65`, `macos-15` + Linux): **todos los jobs en verde** — 48 tests del núcleo (incluidos 16 del proveedor real con cliente simulado), compilación de `HKHealthStoreClient`, apps de iPhone y Apple Watch, `HalsyniOSTests` en simulador y catálogos de 9 idiomas sincronizados. CI detectó un fallo real solo visible en macOS (empate de fuentes de sueño dependiente del orden de un diccionario), corregido con desempate determinista.

## Pendiente por fase

- Fase 2 (pendiente): prueba manual en dispositivo; el mapeo de `HKHealthStoreClient` no tiene tests automáticos porque requiere HealthKit con datos y permisos (se cubre la lógica con el mock).
- Fase 4: máquina de estados de sesión, `PaceEstimator` con trazas GPS sintéticas (ruido, pérdida de señal, pausas), distancia acumulada.
- Fase 5: zonas cardíacas, vueltas, intervalos.
- Fases 3, 6, 8: `HealthScoreEngine`, `RecoveryEngine`, `ReferencePercentileEngine`, `TrainingLoadEngine`.
- UI tests de navegación y snapshots de modo claro/oscuro.
