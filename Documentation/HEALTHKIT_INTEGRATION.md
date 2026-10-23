# Integración con HealthKit

## Arquitectura (Fase 2)

```
Vistas ──▶ HealthDataProviding
              ├─ DemoHealthDataProvider          (datos sintéticos, modo demo)
              └─ LiveHealthDataProvider          (HalsynCore · semántica, testeable en Linux)
                    └─ HealthStoreClient         (protocolo, solo tipos de HalsynCore)
                          ├─ HKHealthStoreClient (HalsynHealthKit · HealthKit real)
                          └─ MockHealthStoreClient (tests)
```

- **Sensores / almacén** (`HKHealthStoreClient`): traduce consultas de HealthKit a tipos propios. No toma decisiones.
- **Semántica** (`LiveHealthDataProvider`): ventanas diarias, sueño por noche, búsqueda del último valor, estados de disponibilidad. Probada con un cliente simulado (`LiveHealthDataProviderTests`).
- **Selección de fuente** (`HealthDataProviderFactory`, `AppModel`, `WatchModel`): demo o Apple Health, guardada por el usuario.

## Permisos

- Solo **lectura** de los tipos de `HealthKitTypeCatalog.coreReadTypes` (11 métricas + entrenamientos). La escritura de entrenamientos y rutas se pedirá en la Fase 4, cuando exista.
- Se piden desde el onboarding (paso "Conecta tus datos") o desde Perfil, siempre tras explicar qué se lee y por qué.
- El usuario puede continuar con datos demo o con permisos parciales.
- **HealthKit no revela si se denegó la lectura de un tipo.** Por eso:
  - `authorizationState()` solo distingue "pendiente de pedir" (`notDetermined`) de "ya se pidió" (`requested`) y "no disponible" (`unavailable`).
  - Si faltan datos se muestra "Sin datos" junto a una ayuda que invita a revisar Ajustes › Salud › Acceso a datos y dispositivos › HÅLSYN, sin afirmar que hubo una denegación.
- El Apple Watch tiene su propio flujo de permisos y lee su almacén local (funciona sin el iPhone). El almacén del reloj contiene solo un subconjunto reciente de los datos.

## Consultas

| Necesidad | API | Detalle |
|---|---|---|
| Valores diarios (pasos, distancia, energía, ejercicio, FC, HRV, respiración, SpO₂) | `HKStatisticsCollectionQueryDescriptor` | Intervalos de 1 día anclados al inicio del día del calendario del usuario. Opción `cumulativeSum` para tipos acumulativos, `discreteAverage` para discretos, `mostRecent` para FC en reposo y VO₂ máx. HealthKit combina las fuentes según la prioridad configurada en Salud, así que **no hay duplicados** entre iPhone y Apple Watch. |
| Último valor (FC en reposo, VO₂ máx.) | `HKSampleQueryDescriptor`, orden por `endDate` descendente, `limit: 1` | Búsqueda hacia atrás: 1 día para la FC en reposo (no se presenta la de ayer como la de hoy), 120 días para el VO₂ máx. Se conserva la fecha real y la UI la muestra ("Último registro · 2 de octubre"). |
| Sueño | `HKSampleQueryDescriptor` de `sleepAnalysis` | Ver abajo. |
| Carreras | `HKSampleQueryDescriptor` de `HKWorkout` con `predicateForWorkouts(with: .running)` | Distancia, FC media y máxima, energía desde `HKWorkout.statistics(for:)`. Cinta si `HKMetadataKeyIndoorWorkout`. La cadencia media no se deriva todavía (Fase 4). |
| Cambios | `HKObserverQuery` por tipo | Un flujo con búfer de 1 elemento; la app agrupa las ráfagas (1 s) y recarga las pantallas. También se recarga al volver a primer plano y con "tirar para actualizar". |

### Sueño

- El sueño del día D es la noche que termina la mañana de D: ventana **[D-1 12:00, D 12:00)**.
- Solo cuentan las fases dormidas (`asleepCore`, `asleepDeep`, `asleepREM`, `asleepUnspecified`); "en cama" y "despierto" no.
- Los intervalos de distintas fuentes que se solapan se **fusionan** antes de sumar.
- El origen mostrado es la fuente con más tiempo dormido en esa noche.

## Estados de una métrica

| Estado | Cuándo | Mensaje |
|---|---|---|
| `available` | Hay valor | — (valor, unidad y origen) |
| `noData` | Sin muestras en el periodo (o lectura no compartida) | "Sin datos en este periodo" + ayuda de permisos |
| `temporarilyUnavailable` | `errorDatabaseInaccessible` (dispositivo bloqueado) | "Protegido mientras el dispositivo está bloqueado" |
| `readFailed` | Otro error de HealthKit | "No se pudieron leer los datos" |
| `notAuthorized` | HealthKit lo indica explícitamente | "Acceso no concedido" |
| `unsupported` | Sin HealthKit en el dispositivo | "No disponible en este dispositivo" |

Las series diarias **no rellenan con ceros** los días sin datos.

## Lo que todavía no hace (y por qué)

- **Puntuación diaria y recuperación**: en modo Apple Health se muestran como "—" hasta que existan sus motores (Fases 3 y 6). No se inventan.
- **Objetivos**: el usuario los creará en la Fase 9; en modo Apple Health MÅL aparece vacío.
- **Caché local / SwiftData**: no hace falta todavía; HealthKit es la fuente de verdad y las consultas son rápidas. Se añadirá con los motores de puntuación.
- **Entrega en segundo plano** (`enableBackgroundDelivery`): no es necesaria hasta el resumen nocturno (Fase 3).

## Probar

- **Simulador de iPhone**: la app Salud del simulador permite añadir datos a mano (pasos, FC, sueño…). Conecta Apple Health en HÅLSYN y comprueba que aparecen.
- **Dispositivo real**: datos reales del Apple Watch; HRV, FC en reposo, VO₂ máx. y fases de sueño solo existen si el reloj los ha medido.
- **Tests automáticos**: `swift test` en `Packages/HalsynKit` (sin HealthKit) y `HalsyniOSTests` (sin pedir permisos).

## Pendiente de verificar en dispositivo

- Disponibilidad de cada tipo por modelo de Apple Watch y versión de watchOS.
- Qué métricas de running se entregan en vivo durante un entrenamiento (Fase 4, `RUNNING_ENGINE.md`).
- Firma con HealthKit en cuentas de desarrollador gratuitas.
