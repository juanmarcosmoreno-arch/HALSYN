# Motor de running (SPRING)

## Estado actual (Fase 4)

Las carreras se registran de verdad en el Apple Watch, sin depender del iPhone.

```
Reloj
 ├─ WorkoutManager (HalsynWatch/Workout)
 │   ├─ HKWorkoutSession + HKLiveWorkoutBuilder  → estado, FC, distancia, energía; guarda el entrenamiento
 │   ├─ CLLocationManager (.fitness, máxima precisión) → puntos GPS
 │   └─ HKWorkoutRouteBuilder                     → ruta (solo puntos fiables)
 └─ RunSessionTracker (HalsynCore, puro y testeado)
     ├─ WorkoutStateMachine   idle → preparing → running ⇄ paused → stopping → ended
     ├─ ActiveTimer           tiempo activo sin pausas
     ├─ GPSDistanceAccumulator
     ├─ PaceEstimator
     └─ LapTracker
```

### Flujo

1. SPRING en el reloj → **Carrera al aire libre** o **Carrera en cinta** (sin GPS). También se puede iniciar desde el iPhone (SPRING › Correr con Apple Watch → `HKHealthStore.startWatchApp`).
2. Se piden permisos (escritura: entrenamiento, ruta, energía, distancia; lectura: FC, energía, distancia, entrenamientos) y ubicación.
3. Pantallas deslizando en horizontal: **controles** (pausa/reanudar, vuelta, terminar) · **métricas** (perfil Easy Run) · **vueltas**.
4. **Terminar** pide confirmación: *Guardar en Apple Health* o *Descartar*. Al guardar se escribe el entrenamiento y su ruta **una sola vez** (el iPhone nunca escribe entrenamientos, así no hay duplicados).
5. Resumen: distancia, tiempo, ritmo medio, FC media y máxima registrada, vueltas.

Hápticos: inicio, pausa, vuelta automática, vuelta manual y guardado. La pantalla siempre activa reduce la frecuencia de actualización a 1 s. `WKBackgroundModes = workout-processing` mantiene la sesión con la muñeca bajada.

**Recuperación**: si watchOS cierra la app durante una carrera, al relanzarla `handleActiveWorkoutRecovery` → `recoverActiveWorkoutSession` recupera la sesión (tiempo, FC y distancia de HealthKit siguen intactos). Los puntos de ruta anteriores al cierre se pierden; la ruta continúa desde ese momento.

### Distancia

- **Fuente principal**: la distancia de `HKLiveWorkoutBuilder` (`distanceWalkingRunning`), que Apple calcula combinando GPS y acelerómetro. Es la que se guarda en Apple Health, así que la que muestra la app coincide con la de Salud.
- **Respaldo**: si HealthKit no entrega distancia, se usa `GPSDistanceAccumulator`:
  1. Descarta puntos con precisión horizontal peor de 25 m.
  2. Descarta saltos imposibles (> 12,5 m/s).
  3. **Anti-deriva**: solo suma cuando el desplazamiento desde el último ancla supera la precisión declarada (entre 3 y 15 m). Parado con el GPS "bailando" ±4 m suma menos de 15 m en 5 minutos (test).
  4. Tras una pausa o 30 s sin señal no une el hueco con una recta.
  5. Desnivel positivo con histéresis de 3 m y precisión vertical ≤ 10 m.
- Validación con trazas sintéticas: recta limpia (±5 m en 2,1 km), ruido de 3 m (< 1,5 %), pista de 400 m con ruido (< 2 % en 4 vueltas), pérdida de señal, puntos inválidos.

### Ritmo

| Ritmo | Cálculo |
|---|---|
| Actual (el que se muestra) | Distancia recorrida en una **ventana móvil de 20 s** sobre la misma distancia que se muestra. Responde a un cambio real (6:00 → 4:00 /km) en ≤ 20 s y no oscila con el ruido punto a punto (5:00 /km ± 25 s con ruido de 3 m). |
| Parado | Si la distancia no avanza en 10 s, el ritmo actual se oculta ("--") en lugar de mostrar un valor viejo. |
| Medio | Distancia total / tiempo activo (sin pausas). |
| Vuelta | Distancia y tiempo desde el inicio de la vuelta. |

Tras pausar o reanudar, la ventana se vacía para no mezclar tramos.

### Vueltas

- **Auto Lap** cada 1 km (configurable en el modelo; el ajuste en la app llega con el editor de la Fase 5). El instante exacto de cruce se **interpola** entre las dos actualizaciones de distancia que lo rodean.
- **Vuelta manual** desde los controles.

### Campos sin dato en vivo

Se muestran como "--", nunca con estimaciones: cadencia (pendiente de verificar en dispositivo), potencia si el reloj no la entrega, zona sin FC máxima configurada, ritmo objetivo e intervalo fuera de un plan.

## SPRING Pro (Fase 5)

```
iPhone: Ajustes de carrera ──WatchConnectivity (applicationContext, JSON)──▶ Reloj: RunSettingsStore
                                                                              │
RunSessionTracker(settings:plan:) ◀───────────────────────────────────────────┘
 ├─ HeartRateZoneConfiguration + ZoneTimeAccumulator   zona actual y tiempo en zonas
 ├─ IntervalTracker(IntervalPlan)                      paso actual, lo que falta
 ├─ RunAlertEngine                                     alertas de ritmo y zona
 └─ RunCue (vuelta, paso, fin del plan, alerta)  ──▶  WorkoutManager: háptico + aviso en pantalla
```

### Zonas cardíacas

- 5 zonas que empiezan al 50, 60, 70, 80 y 90 % (convención de entrenamiento, no diagnóstico).
- **% de la FC máxima** o **reserva cardíaca (Karvonen)**: FC reposo + (FC máx − FC reposo) × %. Karvonen sin una FC en reposo válida (30–100 lpm) vuelve a % de la máxima y se indica.
- FC máxima: **introducida por el usuario** o **la más alta registrada** en sus carreras de Apple Health (se descartan valores fuera de 120–230 lpm, picos del sensor). **No se estima por la edad.** En modo demo no se guardan valores de ejemplo como propios.
- Tiempo en zonas: cada lectura de FC cuenta hasta la siguiente, como máximo 15 s (si el sensor se calla no se extrapola). Las pausas no cuentan.

### Alertas

| Regla | Valor |
|---|---|
| Espera antes de avisar | 10 s seguidos fuera de rango (un pico no avisa) |
| Repetición | cada 60 s mientras sigue fuera |
| Vuelta al rango | aviso "en rango"; en ritmo hay que entrar 3 s/km dentro del rango (histéresis) |
| Sin dato (ritmo "--") | reinicia la espera |
| Pausa | reinicia todo; no hay avisos en pausa |
| Intervalos | el ritmo objetivo de la serie sustituye al de la carrera libre; en recuperación no hay objetivo |

Hápticos: más rápido / por encima de la zona → `directionDown`; más lento / por debajo → `directionUp`; de vuelta en rango → `click`; vuelta automática → `notification`; serie → `start`; recuperación y calma → `stop`; plan completado → `success`.

### Intervalos

- Plan: calentamiento opcional, n × (serie + recuperación) y vuelta a la calma opcional. Tras la última serie no hay recuperación.
- Cada paso termina por **tiempo**, por **distancia** o **al pulsar Vuelta** (abierto).
- El paso por tiempo termina en el segundo exacto aunque no cambie la distancia (el reloj comprueba cada segundo); el de distancia, en el metro exacto. Una actualización tardía puede completar varios pasos y el siguiente empieza desde el cruce, no desde la actualización.
- Al terminar el plan la carrera sigue como libre hasta que el usuario la termina.

### Análisis posterior (iPhone)

- Ruta y FC se leen de Apple Health (`HKWorkoutRouteQuery`, muestras de FC del intervalo del entrenamiento).
- **Parciales**: se recalculan desde la ruta con el mismo filtro GPS que en vivo; el tiempo solo cuenta entre puntos con menos de 30 s de separación (las pausas no inflan el parcial). Son una aproximación y pueden diferir ligeramente de la distancia de Apple Health.
- En modo demo la ruta es un recorrido de ejemplo y se indica.

## Matriz de compatibilidad

Se completará **solo con información verificada** en documentación oficial y en dispositivo físico. Ninguna celda se asume.

| Métrica | API pública | En vivo | Tras el entrenamiento | Dispositivos | Verificado |
|---|---|---|---|---|---|
| Tiempo, distancia, FC, energía | HKLiveWorkoutBuilder | sí (implementado; pendiente de verificar en dispositivo) | sí | Apple Watch con watchOS 10+ | ⏳ |
| Ruta GPS | CLLocationManager + HKWorkoutRouteBuilder / HKWorkoutRouteQuery | sí (implementado) | sí | Apple Watch con GPS | ⏳ |
| Ritmo | derivado de distancia/velocidad | por verificar | por verificar | por verificar | ❌ |
| Cadencia | por verificar | por verificar | por verificar | por verificar | ❌ |
| Potencia de carrera | `.runningPower` | se muestra si HKLiveWorkoutBuilder la entrega; por verificar | por verificar | por verificar | ❌ |
| Longitud de zancada | `.runningStrideLength` | por verificar | por verificar | por verificar | ❌ |
| Oscilación vertical | `.runningVerticalOscillation` | por verificar | por verificar | por verificar | ❌ |
| Tiempo de contacto | `.runningGroundContactTime` | por verificar | por verificar | por verificar | ❌ |
| Elevación / desnivel | CoreLocation / metadatos | por verificar | por verificar | por verificar | ❌ |

## Control de calidad de datos y tipo de esfuerzo (Fase 1 del motor deportivo)

`DataQuality` (HalsynCore/Engines/Running/DataQuality.swift) revisa cada entrenamiento de Apple Health antes de usarlo. **Nunca borra nada**: marca y decide qué cálculos lo usan; el usuario puede forzar usarlo o no (SPRING › Calidad de los datos).

| Marca | Regla | Efecto |
|---|---|---|
| Duplicado | mismo deporte, inicio a ≤ 60 s, duración a ≤ 5 %, distancia a ≤ 3 % | se excluye el de menos datos |
| Superposición | mismo deporte, se pisan > 50 % del más corto | se excluye el de menos datos (indica si es de otra app) |
| Sin distancia | carrera sin distancia | no cuenta para forma ni predicción |
| Muy corto | < 2 min o < 200 m | no cuenta para forma ni predicción |
| Ritmo imposible | correr < 2:40 o > 20:00 min/km; caminar < 4:00 min/km; bici > 80 km/h | no cuenta para forma ni predicción |
| Pulso imposible | media fuera de 35–225, máxima > 230 o media > máxima | se ignora su FC |
| Cadencia 0 | cadencia = 0 | se ignora la cadencia |

"Más datos" = distancia (4) + FC media (2) + FC máxima (1) + cadencia (1) + desnivel (1); a igualdad, el que empezó antes.

`EffortClassifier` clasifica cada carrera por FC media / FC máxima de referencia (la configurada a mano o la segunda más alta observada, para ignorar un pico aislado): < 80 % suave, 80–87 % moderado, ≥ 87 % fuerte, ≥ 90 % sostenido 8–75 min y ≥ 3 km = esfuerzo comparable a una prueba. Sin FC fiable: "desconocido". Test y competición marcados por el usuario tienen prioridad.

`FitnessEstimator` ahora solo usa como prueba de entrenamiento los esfuerzos comparables a una prueba que pasan el control de calidad; si el mejor supera al segundo en más de 5 puntos de VDOT, se toma el segundo. Un rodaje rápido sin pulso alto ya no se toma como esfuerzo máximo. `RacePredictor` también descarta los registros dudosos.

## Modelo de rendimiento y factibilidad (Fase 2a)

- `RacePerformanceModel.assess` reúne tests y competiciones (180 días) y esfuerzos de entrenamiento a tope (42 días, ya filtrados por calidad), los pondera por tipo y antigüedad, estima la tendencia con Theil–Sen, baja el peso de pruebas incoherentes y calcula el VDOT de hoy, su incertidumbre y la confianza (alta / media / baja).
- `PerformanceAssessment.predict(d)` da el tiempo por Daniels y por Riegel (pruebas proyectadas, ponderadas por cercanía de distancia), la combinación (media geométrica) y un intervalo del 80 % con 3 pruebas o más.
- `RacePrediction.from(_:)` alimenta la tarjeta de predicción; sin pruebas se usa el Riegel clásico de `RacePredictor`.
- `GoalProbability.evaluate(plan:performance:…)` da la categoría de factibilidad, el tiempo previsto con su rango y los factores a favor y en contra. No se muestra porcentaje (sin calibrar).
- `FitnessEstimator` sigue dando el VDOT con el que se generan los ritmos del plan (se unificará en la fase 3).

## Zonas por FC umbral y carga (Fase 2b)

- **Zonas por FC umbral** (`HeartRateZoneMethod.lactateThreshold`, Friel): Z1 desde el 65 %, Z2 85 %, Z3 90 %, Z4 95 %, Z5 100 % de la FC umbral; Z5 llega a la FC máxima (o 110 % del umbral). Sin FC umbral válida (110–210) se usa el % de la máxima. `isApproximate` = zonas que salen de la FC máxima *observada* (la real puede ser más alta).
- **Carga por tramos**: `BanisterTRIMP.load(samples:)` suma el TRIMP de cada intervalo entre lecturas de FC (máximo 15 s por tramo, ≥ 10 lecturas). Se usa para las sesiones de las últimas 6 semanas; las anteriores, con la FC media.
- **Carga por ritmo** (sin FC): intensidad = 0,85 × ritmo umbral / ritmo de la sesión (acotada 0,3–1), en la misma escala TRIMP, marcada como aproximada. El ritmo umbral sale del modelo de rendimiento (VDOT).
- **Monotonía y strain** (Foster 1998): media / desviación de la carga diaria de 7 días (días sin entrenar = 0) y carga semanal × monotonía. ≥ 2 se describe como "alta". Se presenta como descripción del entrenamiento, no como predictor de lesiones.
- Los duplicados y superposiciones (`DataQuality`) no suman carga.

## Plan adaptativo y molestias (Fase 3)

`PlanAdvisor` (HalsynCore/Engines/Running/PlanAdvisor.swift) ajusta **solo los próximos 7 días**, sin tocar el plan guardado: el ajuste se aplica al mostrarlo y al enviarlo al reloj (`TrainingPlanStore.displayPlan`) y el usuario puede rechazarlo ("Mantener el plan original").

| Regla | Condición | Ajuste |
|---|---|---|
| Fatiga (2 de 3 señales) | recuperación baja 2 de 3 días; km de 7 días ≥ 1,5 × media semanal previa (≥ 10 km); ≥ 3 carreras "fuertes" en 7 días | la próxima exigente de 4 días → rodaje suave (80 %); tirada larga de esos días al 85 % (no en semana de carrera) |
| Molestia 4–6 | activa (14 días, sin resolver) | exigentes de la semana → suave; tirada larga al 80 % |
| Dolor ≥ 7 | activa | descanso 3 días, suave el resto; se sugiere consultar |
| Seguridad | dos exigentes en días seguidos | la segunda → suave |

Cada ajuste lleva su motivo con los datos (p. ej. "Tu recuperación estuvo baja 2 de los últimos 3 días (media 44; lo habitual en ti es 72)"). El reajuste semanal de volumen (`TrainingPlanGenerator.replan`), las semanas de asimilación y el afinamiento siguen como antes.

## Evolución y explicaciones (Fase 4)

- `RunnerProgress.build` (sin fuga de futuro: cada punto semanal del modelo solo ve datos hasta ese día) da el VDOT y el 5 km previsto semana a semana, las semanas de entrenamiento (km, minutos, carreras y minutos suaves / moderados / fuertes por `EffortClassifier`), los mejores tiempos observados del último año (carreras entre −1 % y +6 % de la distancia, llevadas a la distancia exacta con Riegel) y el pulso a un ritmo de referencia (mediana de tus ritmos) por períodos de 4 semanas, con una recta de Theil–Sen ritmo → FC (≥ 4 carreras, sin extrapolar).
- `PeriodComparison` compara 4, 8 o 12 semanas con el período anterior.
- `CoachInsights` genera frases solo si se superan umbrales documentados (ver la tabla en el código): 5 km previsto ±10 s, FC a igual ritmo ±3 lpm, > 30 % de minutos fuertes, volumen ×1,3 o ×0,6, FC en reposo ≥ línea basal + max(3, 1,5 × MAD), recuperación ±8 puntos, regularidad y confianza baja.
- La pantalla **Evolución** (SPRING) separa lo observado (tests, carreras, mejores tiempos) de lo estimado por el modelo, y el VDOT del VO₂ máx. del Apple Watch.

## Validación: evaluación retrospectiva y calibración (Fase 5)

- `PredictionBacktest.run` predice cada test o competición registrada con el modelo armado **solo con datos anteriores a ese día** (resultados y carreras previas; se excluye el propio entrenamiento del resultado) y mide MAE (s y %), RMSE, sesgo (positivo = pesimista), cobertura del rango del 80 % y el error relativo robusto (MAD × 1,4826).
- Con 5 casos o más, ese error calibrado se usa para que los rangos de las predicciones nunca sean más estrechos que tu error real (`predict(_:calibratedRelativeError:)`).
- `GoalOutcome` guarda, cuando registras como competición la carrera del plan (distancia ±2 %, fecha ±3 días), el valor que daba el modelo una semana antes. `GoalCalibration`: puntuación de Brier; el porcentaje de factibilidad solo se muestra con ≥ 5 objetivos y Brier < 0,25.
- Pantalla **Precisión del modelo** (Predicción y Evolución) con todas las métricas y cada caso.
- Tests: fórmulas (tablas de Daniels, Riegel, Theil–Sen, TRIMP, Foster), datos faltantes, duplicados, unidades, valores extremos, estabilidad (un rodaje suave no mueve el modelo), compatibilidad con datos guardados antes (zonas sin FC umbral) y ausencia de fuga de información futura.

## Auditoría del motor de predicción (0.10.0 (95))

**Problemas encontrados con datos reales** (exportación del usuario): VDOT 33,4 por debajo de sus dos tests (33,6 y 35,1) porque un rodaje (VDOT 30,5) detectado como esfuerzo entraba al promedio; test del 31/10 contado dos veces (uno cargado a mano con 3,00 km y otro marcado desde el entrenamiento con 3,026 km); proyección lineal; rango sin aclarar que no está calibrado; adherencia "3 de 3" con un plan recién empezado.

**Cambios:**
- **Selección de pruebas** (`RacePerformanceModel.assess`): competiciones (peso 1) y tests (0,9) son la base; los esfuerzos detectados en entrenamientos (solo al aire libre) **solo pueden subir** la estimación (peso 0,5); un entrenamiento por debajo se muestra como "no baja tu forma" con peso 0. Sin resultados oficiales, el mejor esfuerzo (con la regla de valor aislado).
- **Duplicados de resultados** (`deduplicated`): mismo día, tiempo a ≤ 2 % y distancia a ≤ 3 % → el mismo esfuerzo; se queda el que viene del entrenamiento de Salud. Al marcar un entrenamiento como test, el resultado manual equivalente se reemplaza. Dos esfuerzos distintos del mismo día no se fusionan.
- **Tendencia** solo con tests y competiciones (≥ 3 en ≥ 21 días); si no, provisional.
- **Incertidumbre**: dispersión ponderada (mín. 0,8) × √(1 + 1/n efectivo de Kish) + 0,5 sin prueba oficial reciente: pocas pruebas, o pruebas casi iguales, no dan rangos estrechos.
- **Rendimiento actual frente a proyección** (`GoalProjection`): mejora con rendimientos decrecientes 4 × (1 − e^(−semanas·ritmo·factor/4)); escenarios conservador (1 punto / 12 semanas), central (1/6, o mitad tendencia propia con 3+ tests) y optimista (1/4); incertidumbre √(hoy² + (½ mejora)² + (0,15·√semanas)² + 0,7²).
- **Adherencia** (`TrainingAdherence`): sesiones del plan cumplidas, frecuencia real frente a la del objetivo, semanas con plan y carreras fuera del plan; para la proyección cuenta el menor entre adherencia y frecuencia.
- **Rangos orientativos**: se dice explícitamente que no están calibrados hasta tener ≥ 5 casos con cobertura observada entre 65 y 95 % (`rangeIsCalibrated`).
- **Validación de la proyección** (`PredictionBacktest.runProjection`): cada test o competición proyectado desde 4 semanas antes, por separado de la validación del rendimiento de hoy. Gráfico de evolución del error.
- **Tendencias**: el cambio del 5 km previsto se compara con la variación normal del modelo (±1 σ); solo se llama "real" si la supera.
- **Simulador** (`GoalSimulation`): distancia, fecha, tiempo y días por semana; escenarios con sus supuestos. La frecuencia aporta 0,4 / 0,6 / 0,85 / 1 de la mejora con 1 / 2 / 3 / 4+ días; más de 4 días no suma.
- **Calidad**: cadencia fuera de 100–260 pasos/min se marca y se ignora.

## Auditoría de noviembre (0.10.0 (100))

Detalle y casos reales en `AUDITORIA_NOV_2026.md`.

- **Pesos del VDOT** (`PerformanceEvidence.WeightFactors`): tipo × antigüedad ×
  distancia × calidad × tope × coherencia. Los entrenamientos suman como mucho
  la mitad del peso de los tests y competiciones. `countedEvidence` y
  `valueUsed` reproducen exactamente el VDOT mostrado.
- **Duplicados**: mismo identificador de Salud siempre; corrección manual con
  `distinct`.
- **Cumplimiento**: `SessionSkipReason` (enfermedad y lesión no cuentan) y días
  con eventos de salud que impiden entrenar.
- **Intensidad** (`IntensityClassifier`): reglas en el código. Sin pulso nunca
  se clasifica como «a tope».
- **Volumen** (`TrainingVolumeAnalysis`): 12 semanas completas, medias 4/8/12,
  Theil–Sen, descanso, rachas y aumento brusco relativo a tu historial.
- **Plan**: un evento de salud reciente quita la intensidad; nada compensa lo perdido.

## RacePerformanceModel 1.4 (0.10.0 (102))

- FC máxima de referencia con **todas** las carreras (antes solo aire libre).
- `VDOTEligibility`: confirmado / candidato / no elegible (motivo). Criterios en
  `EffortClassifier.eligibility`. La intensidad fisiológica `veryHard` no implica
  elegibilidad.
- Rol `notMaximal`: candidato más de 3 puntos por debajo de los tests.
- Confirmar o descartar esfuerzos a mano (`FitnessStore.rejected`).
- Detalle en `AUDITORIA_RPM_1_3.md`.

## RacePerformanceModel 1.5 (0.10.0 (106))

- «Hoy» = Daniels con el VDOT actual (una sola definición); Riegel ensancha el rango.
- Cumplimiento frente a las sesiones programadas en los días transcurridos y
  mezcla con el supuesto central cuando hay pocas sesiones (`projectionCompliance`).
- Referencia de FC máxima sin duplicados; `effectiveMax` cuando la configurada
  queda por debajo de lo registrado.
- Deduplicación determinista (±12 h); sesiones de umbral o series planificadas
  no elegibles; semanas restadas por eventos de salud con fin conocido.
- Detalle en `AUDITORIA_MOTORES_FASE_B.md`.

## RacePerformanceModel 1.6 (0.10.0 (107))

**FC máxima: tres valores separados.**
- **Configurada**: la que introdujiste. Se conserva en `configuredMaxHeartRate`, aunque elijas otra fuente.
- **Registrada**: la más alta presente en Salud, sin duplicados ni pulso inválido.
- **Validada** (`MaxHeartRateValidator`): el valor más alto alcanzado (±1 lpm) en al menos dos sesiones distintas de los últimos 12 meses. Se descartan:
  - un máximo de Salud que supera en más de 3 lpm al pico sostenido 15 s en las muestras;
  - un máximo más de 50 lpm por encima de la media, en una carrera de 10 min o más y sin muestras que lo confirmen.
  - Con una sola sesión utilizable, la validada es provisional.

Desde la 1.6 la configurada **no se reemplaza en silencio**: con la fuente manual se usa la tuya. Si queda más de 2 lpm por debajo de la validada, se avisa y se ofrece «Usar la validada». En el caso real eso significa 182 hasta que elijas otra fuente (validada 186, registrada 189).

**Intensidad.**
- Jerarquía de evidencia:
  1. FC umbral (Friel);
  2. zonas por reserva (Karvonen);
  3. % de la máxima;
  4. ritmo;
  5. RPE;
  6. desconocida.
- El RPE (1–10, Borg CR-10) se anota por entrenamiento. Se guarda aparte: la intensidad percibida no reemplaza a la fisiológica, y se marca cuando difieren 2 niveles o más.
- `planCompliance` puede ser `as_planned`, `harder` o `easier`.

**Adaptación individual** (`IndividualAdaptationModel` 1.0).
- Pendiente del VDOT de tus tests y competiciones por mínimos cuadrados ponderados:
  - σᵢ = 0,7 ÷ √(tipo × distancia × calidad);
  - antigüedad con vida media de 12 semanas;
  - Huber con c = 1,5, en 3 iteraciones;
  - sobredispersión χ²/(n − 2).
- Se combina con una referencia N(1/6 × f_cumplimiento × f_frecuencia, 0,10²) por precisiones, de modo que el peso de tu evidencia sale de la información disponible.
- Estados:
  - referencia: menos de 3 pruebas o menos de 21 días;
  - aprendiendo;
  - personalizada: peso ≥ 50 %, 4 pruebas o más y 42 días o más.
- Acotada a ±0,25 VDOT por semana. No usa la carga como predictor.

**Proyección.**
- Media = VDOT actual + ganancia acotada con la tasa combinada.
- σ² = forma actual² + (pendiente × σ_tasa)² + (pendiente × σ_adherencia)² + horizonte² + día de carrera².
- Los escenarios son los percentiles 10, 50 y 90 de esa distribución, no tasas fijas.
- El factor de cumplimiento es una rampa continua: (c − 0,4) ÷ 0,6 entre 0 y 1. Antes llegaba a 1 en el 90 %; ahora la proyección puede ser algo más lenta, y eso es intencional.

**Validación.** El backtest guarda el horizonte de cada caso y muestra el error por horizonte (≤ 14 d, 15–42 d, > 42 d). Con menos de 5 casos muestra «Datos insuficientes para validar».

## Récords personales (`RunRecords` 1.0, 0.10.0 (109))

**Categorías**
- Kilómetro más rápido, 5 km más rápidos y 10 km más rápidos.
- Distancia más larga y carrera más larga en tiempo.

**Cómo se mide**
- **Tiempos**: la mejor suma de kilómetros completos y seguidos. Los parciales de 1 km se interpolan con `LapTracker`, en el reloj y en el iPhone por igual.
  - Solo carreras al aire libre con GPS: en cinta la distancia es estimada.
  - Si algún kilómetro está por debajo de 2:30 o por encima de 20:00, la carrera no cuenta para los tiempos (salto del GPS o pausa).
- **Distancia y duración**: de la carrera entera, también en cinta, con 1 km como mínimo.

**Puestos**
- Puesto = 1 + carreras anteriores estrictamente mejores.
- Se marcan el 1.º, el 2.º y el 3.º, solo si hay al menos tantas carreras anteriores como el puesto. Así, la primera carrera no es un récord y ser 2.ª de dos no cuenta.

**Reparto entre iPhone y reloj**
- El iPhone calcula cada carrera una vez (lee su ruta de Salud), sin duplicados ni carreras excluidas.
- Le pasa al reloj una tabla con las 3 mejores de cada categoría y cuántas carreras hay.
- Al terminar, el reloj compara la carrera con esa tabla, vibra y muestra el puesto en el resumen. Después suma la carrera a su tabla hasta que llegue la nueva del iPhone.
- En el iPhone, cada carrera muestra los puestos que obtuvo el día que se corrió, y hay una pantalla con los 3 mejores de cada récord.

## Equivalencia en cinta (`TreadmillEquivalent`, 0.10.0 (113))

- **1 % de inclinación equivale a correr en llano al aire libre** (Jones & Doust, *J Sports Sci* 1996): compensa la falta de resistencia del aire.
  - Se midió entre 2:51 y 4:43 min/km.
  - A ritmos más lentos el 1 % queda algo más exigente que la calle: es una aproximación prudente.
- **Con 2 % o 3 %**, la velocidad equivalente sale de la ecuación de carrera del ACSM, en la que el coste por metro es proporcional a 0,2 + 0,9 × pendiente:
  - v_cinta = v_calle × 0,2 ÷ (0,2 + 0,9 × (pendiente − 0,01));
  - se redondea a 0,1 km/h.
- **Guía por sesión**:
  - calentamiento y calma de 2 km al ritmo suave del plan;
  - series o bloque al ritmo objetivo;
  - recuperaciones de 2 min caminando o trotando;
  - el test se recomienda al aire libre, porque en cinta la distancia es estimada.
- **Durante la sesión en cinta**, el reloj muestra en el pie la velocidad a poner, con la inclinación elegida, en lugar del ritmo objetivo.
