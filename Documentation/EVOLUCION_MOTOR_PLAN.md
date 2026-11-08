# Evolución del motor de rendimiento y recuperación — plan

Objetivo: RacePerformanceModel 1.6 y RecoveryEngine 0.4. HealthScoreEngine solo
se toca si hace falta (no hace falta).

## Archivos que se modifican

| Fase | Archivo | Cambio |
|---|---|---|
| 1 | `HalsynCore/Engines/Running/MaxHeartRate.swift` (nuevo) | FC máxima registrada, validada (repetida en ≥ 2 sesiones, con pico sostenido si hay muestras) y configurada, con su justificación |
| 1 | `Engines/Running/HeartRateZones.swift` | Fuente `validated`; se guarda la FC configurada aparte para no perderla al cambiar de fuente |
| 1 | `Engines/Running/DataQuality.swift` | La referencia de FC máxima pasa por el validador |
| 1 | `Engines/Running/WorkoutIntensity.swift` | Jerarquía de evidencia (umbral → zonas personales → FC máx. validada → ritmo → RPE → sin clasificar); RPE e intensidad percibida aparte; cumplimiento de la intensidad prevista |
| 1 | `Engines/SleepAnalysis.swift` | Episodios con fecha y hora reales, fecha de atribución (sueño principal → día en que despiertas; siesta → día en que empieza), mediodía local correcto en cambios de horario |
| 2 | `Engines/Running/IndividualAdaptation.swift` (nuevo) | Regresión bayesiana con incertidumbre por prueba, previa conservadora (pauta de Daniels), reponderación de Huber y estados referencia, aprendizaje y personalizado |
| 2 | `Engines/Running/GoalProjection.swift`, `GoalProbability.swift` | Escenarios = percentiles 10/50/90 de la distribución predictiva; incertidumbre de la tendencia y de la adherencia; factor de cumplimiento continuo |
| 3 | `Engines/Running/PredictionBacktest.swift` | Error por horizonte y validación de la proyección con el modelo nuevo |
| 3 | `Engines/RecoveryEngine.swift` | 0.4: HRV alta no suma por encima de +1 desviación, agregación que no compensa del todo una señal adversa, contexto (enfermedad, sesión intensa reciente), avisos |
| 4 | App: Ajustes › Zonas, detalle del entrenamiento (RPE), «Evolución del rendimiento», «¿Cómo aprende HÅLSYN?», «¿Por qué tengo este puntaje?», exportación (esquema 4) | Interfaz, explicaciones y exportación |

## Riesgos de compatibilidad

- **Ajustes guardados**: `HeartRateZoneConfiguration` gana un campo opcional
  (`configuredMaxHeartRate`), que se decodifica como `nil` en ajustes
  antiguos. Si la fuente era `manual`, el valor actual se toma como el
  configurado. La fuente nueva `validated` no la entiende el reloj con una
  versión vieja: hay que instalar las dos apps juntas.
- **FC máxima**: desde la 0.10.0 (106), si la configurada quedaba por debajo de
  lo registrado, HÅLSYN usaba la observada **sin cambiar el ajuste**. A pedido
  («no cambiar silenciosamente»), ahora se usa la que elijas; si es la
  configurada y queda por debajo de la validada, se avisa y se ofrece cambiarla.
  Con 182 configurada, las intensidades vuelven a calcularse con 182 hasta que
  elijas «Validada».
- **Escenarios**: el conservador y el optimista dejan de ser «1 punto cada 12 o
  cada 4 semanas» y pasan a ser los percentiles 10 y 90 de la distribución
  predictiva. Los valores cambian.
- **Factor de cumplimiento**: pasa de una rampa del 40 al 90 % a una rampa
  continua del 40 al 100 %, sin el corte en 90 %. Con 93 % el factor baja de
  1,00 a 0,88: menos favorable, pero sin saltos.
- **Recuperación**: los puntajes bajan algo cuando una señal es adversa (ya no
  la compensan del todo las favorables) y cuando la HRV está muy por encima de
  lo habitual.
- **Exportación**: esquema 4. Las columnas nuevas van al final, ninguna se
  renombra; hay un CSV nuevo de episodios de sueño.
- **Sueño**: el sueño de cada día pasa a ser el principal más las siestas que
  empiezan ese mismo día. `sleep_h` mantiene su significado anterior (ventana de
  mediodía a mediodía) para no romper comparaciones.
