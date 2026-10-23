# Pruebas

## Suites

| Suite | Framework | Dónde | Cubre |
|---|---|---|---|
| `Packages/HalsynKit/Tests/HalsynCoreTests` | Swift Testing | `swift test` (Linux/macOS) y ⌘U en Xcode | Marca, contraste WCAG de tokens, ritmo y formatos, disponibilidad de datos, `MetricDisplay`, proveedor demo (determinismo, rangos, etiquetado), perfiles de pantalla, generador determinista |
| `Packages/HalsynKit/Tests/HalsynCoreTests/LiveHealthDataProviderTests.swift` | Swift Testing | igual | Proveedor real con `MockHealthStoreClient`: permisos, estados de error, sueño (fases, solapes, ventana), último valor y su fecha, series sin ceros, sin puntuaciones inventadas |
| `Packages/HalsynKit/Tests/HalsynCoreTests/HealthScoreEngineTests.swift` | Swift Testing | igual | Curvas del motor, día parcial y descanso sin penalización, tope de pasos, carga, cobertura mínima, renormalización, pesos configurables, puntuación demo/real, resumen del día |
| `Packages/HalsynKit/Tests/HalsynCoreTests/RunningEngineTests.swift` | Swift Testing | igual | GPS (recta, ruido, parado, curvas, saltos, pérdida de señal, desnivel), ritmo (estable, cambio, ruido, parada), máquina de estados, tiempo activo, vueltas, sesión completa con pausa, prioridad de la distancia de HealthKit, FC, campos sin dato |
| `Packages/HalsynKit/Tests/HalsynCoreTests/SpringProTests.swift` | Swift Testing | igual | Zonas (% máx., Karvonen, valores no plausibles, FC máx. observada), tiempo en zonas con huecos y pausas, intervalos (expansión, tiempo/distancia/abierto, actualizaciones tardías, sesión completa con avisos), alertas (picos, espera, repetición, histéresis, sin dato, zona, pausa), ajustes (JSON, datos dañados, normalización de pantallas), parciales desde la ruta (pausas, millas), zonas desde muestras, ruta demo determinista |
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

Fase 3, GitHub Actions (commit `20d3b54`): **todos los jobs en verde** — 70 tests del núcleo (22 nuevos de `HealthScoreEngine`, cálculo desde proveedores y resumen del día), apps de iPhone y Apple Watch, `HalsyniOSTests` (incluidos textos de factores y resumen) y catálogos de 9 idiomas (308 cadenas).

Fase 4, GitHub Actions (commit `0e66974`): job de iOS + watchOS **en verde** — compilación de `WorkoutManager` (HKWorkoutSession, HKLiveWorkoutBuilder, HKWorkoutRouteBuilder, Core Location), pantallas de carrera del reloj, inicio desde el iPhone y 91 tests del núcleo (21 nuevos con trazas GPS sintéticas). Los tests encontraron un fallo real del filtro GPS (parado con ruido sumaba 378 m), corregido antes del commit. Pendiente: carrera real con Apple Watch.

Fase 5, GitHub Actions (commit `029535f`): **todos los jobs en verde** — 133 tests del núcleo (42 nuevos: zonas, alertas, intervalos, ajustes, parciales), apps de iPhone y Apple Watch (WatchConnectivity, MapKit, editor de ajustes, página de intervalos), `HalsyniOSTests` y catálogos de 9 idiomas (436 cadenas). Pendiente: probar en el reloj real.

Fase 6, GitHub Actions (commit `7e2e7b7`): **todos los jobs en verde** — 151 tests del núcleo (sueño por noche, regularidad, hipnograma, `RecoveryEngine`), apps de iPhone y Apple Watch, `HalsyniOSTests` y catálogos de 9 idiomas. `ChartSnapshotTests` renderiza 7 gráficas en claro y oscuro (14 capturas, artefacto `capturas-graficas`); en su primera ejecución detectó un rango invertido en el gráfico de horarios que habría cerrado la app.

## Pendiente por fase

- Fase 2 (pendiente): prueba manual en dispositivo; el mapeo de `HKHealthStoreClient` no tiene tests automáticos porque requiere HealthKit con datos y permisos (se cubre la lógica con el mock).
- Fase 4 (pendiente): carrera real en dispositivo (precisión, batería, muñeca bajada, sin iPhone, recuperación).
- Fase 5 (pendiente): hápticos, intervalos, mapa y sincronización de ajustes en dispositivo físico.
- Fases 5, 6, 8: `TrainingLoadEngine`, `RecoveryEngine`, `ReferencePercentileEngine`.
- UI tests de navegación y snapshots de modo claro/oscuro.
