# Auditoría técnica de los motores — Fase A (sin cambios de código)

Versiones auditadas: RacePerformanceModel 1.4, RecoveryEngine 0.3,
HealthScoreEngine 0.1-provisional, exportación formato 3 (0.10.0 (105)).
Método: lectura del código y sondas con el caso real (`NovemberFixture`:
49 carreras de la exportación del 7/11/2026). Las sondas se borraron; no se
modificó ningún motor.

Clasificación: **E** error confirmado · **R** riesgo potencial ·
**L** limitación metodológica · **C** comportamiento correcto que necesita explicación.

## 1. RacePerformanceModel

| # | Hallazgo | Archivo · función | Evidencia | Impacto | Prioridad | Corrección propuesta |
|---|---|---|---|---|---|---|
| 1.1 | **C** Ecuaciones de Daniels–Gilbert correctas | `VDOT.swift` · `oxygenCost`, `sustainableFraction`, `value`, `raceTime` | Coeficientes −4,60 / 0,182258 / 0,000104 y 0,8 / 0,1894393 / 0,012778 / 0,2989558 / 0,1932605; bisección de 80 iteraciones. 3,026 km en 15:51 → 35,0852; 4,005 km en 22:06 → 33,6265 | — | — | Ninguna. Corregir la doc: dice «3,5 min a 5 h» y el rango es 3,5–420 min |
| 1.2 | **C** VDOT combinado | `RacePerformanceModel.assess` | Precisión completa: (35,0852 × 0,80181 + 33,6265 × 0,82872) ÷ 1,63053 = **34,3439**. Antigüedad 0,5^(7/42) = 0,8909 y 0,5^(5/42) = 0,9208 × tipo 0,9. Se redondea solo al mostrar | — | — | Ninguna |
| 1.3 | **E** Dos «tiempos de hoy» distintos | `GoalProbability.evaluate` (`currentTime` = solo Daniels) frente a `PerformanceAssessment.predict` (media geométrica Daniels–Riegel) | Mismo modelo: 27:24 (Daniels, «Tu objetivo» y exportación) frente a 27:29 (combinado, tarjeta de Predicción) | Pantallas y exportación no coinciden | Alta | Una sola definición de «hoy» para todas las vistas, documentada |
| 1.4 | **E** La referencia de FC máxima cambia con reimportaciones | `FitnessEstimator.trainingEfforts` / `EffortClassifier.referenceMaxHeartRate` (2.ª más alta) | Con las 49 carreras duplicadas: referencia 186 → **189** y el 1/11 deja de ser candidato. La pantalla Correr limpia antes (`WorkoutQualityStore.clean`), pero `DataExportView` y `TrainingLoadViews` pasan carreras sin limpiar a `FitnessStore.performance` | Resultados distintos según la pantalla o tras reimportar | Alta | Calcular la referencia sobre entrenamientos deduplicados y pasar siempre datos limpios al modelo |
| 1.5 | **E** Deduplicación de resultados dependiente del orden | `RacePerformanceModel.deduplicated` | Dos resultados manuales equivalentes: `kept` cambia si se invierte el orden de entrada | No es determinista ni idempotente frente al orden | Media | Desempate total: con entrenamiento > más antiguo por fecha > id |
| 1.6 | **R** Al agregar un resultado de un entrenamiento se **borra** el manual equivalente | `FitnessStore.add` | `results.removeAll { other.workoutID == nil && … }` | Se pierde trazabilidad (pide conservar duplicados) | Media | No borrar: dejar los dos y que la deduplicación excluya |
| 1.7 | **R** Duplicados solo el mismo día de calendario | `deduplicated` (`isDate(inSameDayAs:)`) | Un resultado manual a las 00:05 de un test terminado a las 23:50 no se detecta | Bajo | Baja | Ventana de ±12 h alrededor del entrenamiento |
| 1.8 | **L** Sesiones tempo y de series planificadas pueden ser candidatas | `EffortClassifier.eligibility` | Solo excluye las suaves, largas y de recuperación planificadas | Un umbral a tope puede subir el VDOT sin confirmación (solo sube) | Media | Excluir también tempo y series planificadas, o sin plan pero con estructura de series; quedan como «confirmable» |
| 1.9 | **C** «very_hard» no implica «confirmed» | `IntensityClassifier` / `eligibility` | Separados desde 1.4; los candidatos no confirmados nunca bajan el VDOT | — | — | Ninguna |
| 1.10 | **R** La validación retrospectiva usa otro modelo | `PredictionBacktest.run` / `runProjection` | Llama a `assess` sin `distinct`, `rejected`, `plannedKinds` ni umbral | La precisión medida no es la del modelo en vivo | Media | Pasar los mismos parámetros |

## 2. Proyección y cumplimiento

| # | Hallazgo | Archivo · función | Evidencia | Impacto | Prioridad | Corrección propuesta |
|---|---|---|---|---|---|---|
| 2.1 | **E** Frecuencia de una semana parcial sin normalizar | `TrainingAdherence.evaluate` | Ventana del 2/11 al 7/11 = 5 días (0,71 semanas) → `actualRunsPerWeek` = 3 carreras **sin dividir** por las semanas → 3 ÷ 4 = 0,75 → factor 0,70. Las 3 sesiones programadas hasta ayer se hicieron todas | Mejora 0,92 en vez de 1,25 VDOT; proyección ~12 s más lenta (26:48 frente a 26:36 con el fixture; 26:46 frente a ~26:34 en la exportación) | **Alta** | Comparar los días con carrera con las sesiones **programadas** en los días transcurridos, no con 4 × semanas. Con datos escasos (< 2 semanas o < 4 sesiones), acercar el valor al supuesto del escenario según el tamaño de la muestra, con la regla documentada |
| 2.2 | **C** Fórmula de mejora: unidades y saturación | `GoalProjection.gain` | ΔVDOT = 4 × (1 − e^(−s·r·f/4)): s en semanas, r en VDOT/semana → VDOT. Derivada en 0 = r·f (lineal al principio); tope de 4 puntos. 0 semanas → 0 | — | — | Ninguna. Documentar que el tope de 4 y la forma exponencial son supuestos de HÅLSYN, no una ley |
| 2.3 | **L** El afinamiento se resta; las semanas de descarga no | `GoalCoach.trainingWeeks` | (72 días ÷ 7, entero) 10 − 1 de afinamiento = 9; la semana parcial se descarta | Leve sesgo conservador | Baja | Documentar; opcionalmente contar la fracción de semana |
| 2.4 | **L** El cumplimiento se pasa a factor de forma lineal entre 40 % y 90 % | `GoalProbability.gainFactor` | (0,75 − 0,4) ÷ 0,5 = 0,70 | Supuesto sin validar | Media | Mantener, explicarlo en pantalla y marcarlo como supuesto |
| 2.5 | **L** Enfermedad e interrupciones | `GoalProjection` | Solo actúan a través de la adherencia (sesiones excusadas). No reducen las semanas efectivas | Proyección optimista tras una enfermedad larga | Media | Restar de las semanas efectivas los días con un evento de salud que impide entrenar (documentado) |
| 2.6 | **C** Pocos tests | `GoalProjection.project` | Con menos de 3 tests no se usa la tendencia personal (pauta de Daniels 1/6) y la incertidumbre sube | — | — | Ninguna |
| 2.7 | **C** Intervalo orientativo | `GoalProjection`, `GoalProbability` | σ = √(forma² + (½ mejora)² + (0,15√semanas)² + 0,7²) = 1,37. Rotulado «orientativo, sin calibrar» en pantalla y exportación; la calibración (n ≥ 5, cobertura, Brier) existe en `PredictionBacktest` y `GoalCalibration` | — | — | Desglosar σ por componentes en pantalla (prueba, mejora, horizonte, día de la carrera) |

## 3. Entrenamiento e intensidad

| # | Hallazgo | Archivo · función | Evidencia | Impacto | Prioridad | Corrección propuesta |
|---|---|---|---|---|---|---|
| 3.1 | **E (dato)** FC máxima configurada por debajo de la registrada | Ajustes › Zonas (`configuredMaxHeartRate`) | Con ≈184 configurada: 4/11 161 lpm → 87,5 % (tempo); 6 y 7/11 166 → 90,2 % (very_hard). Registrado: 189 y dos veces 186. Con 186: 86,6 % (moderado) y 89,2 % (tempo) | Rodajes suaves clasificados como muy intensos | Alta | Aviso ya añadido en la 105. Además: usar la referencia observada cuando la configurada quede por debajo de lo registrado, y avisar |
| 3.2 | **R** La intensidad usa solo % de la FC máxima, ignorando el método de zonas elegido | `IntensityClassifier` | Las zonas pueden ser por reserva de FC o por umbral; la clasificación no | La intensidad no coincide con las zonas que ve el usuario | Media | Usar el método configurado (reserva con FC en reposo, umbral si hay FC de umbral) |
| 3.3 | **L** Falta la discrepancia entre lo planificado y lo observado | — | 6/11 planificada suave y hecha very_hard/hilly; 7/11 larga a 89–90 % | El usuario no ve que se pasó de intensidad | Media | Aviso «Planificada suave · hecha intensa» con FC y desnivel, sin tocar el objetivo de la sesión |
| 3.4 | **L** Desnivel y deriva cardíaca | `IntensityClassifier` | El desnivel solo cuenta para la elegibilidad; no hay deriva (hace falta ritmo y pulso por tramos) | 6/11 (21 m/km) parece más intenso de lo que fue | Baja | Indicar el desnivel en la explicación; la deriva queda para cuando haya muestras de ritmo |
| 3.5 | **R** La exportación clasifica sin muestras de pulso | `DataExportView.prepare` | `IntensityContext.intensities(workouts)` sin `samples`: no detecta series; la pantalla sí las detecta | La exportación puede diferir de la interfaz | Media | Usar las mismas muestras, o exportar «intervals_not_evaluated» |

## 4. RecoveryEngine 0.3

| # | Hallazgo | Archivo · función | Evidencia | Impacto | Prioridad | Corrección propuesta |
|---|---|---|---|---|---|---|
| 4.1 | **C** 7/11 = 84 | `RecoveryEngine.evaluate` | HRV 78 (media de 7 días 34,2 ms frente a una basal de 32,9 ms) · FC 89 (60 frente a 65) · sueño 96 · carga 72 (×1,70). Aporte frente a la base de 75: HRV +1,1 · FC +3,5 · sueño +5,3 · carga −0,5 → 84,4 | — | — | Mostrar estos aportes en puntos (la fórmula lineal lo permite) |
| 4.2 | **L** «Carga reciente» = minutos de ejercicio de Apple | `.recentLoad` | Incluye caminatas y cualquier actividad vigorosa; no es TRIMP | Proxy grueso (15 % del peso) | Media | Usar TRIMP cuando exista, con los minutos como respaldo, y documentarlo |
| 4.3 | **L** Varias mediciones de HRV por día se promedian | `MetricKind.dailyAggregation` (`.average`) | SDNN de contextos distintos (noche, Respirar, día) | Ruido; SDNN no es RMSSD | Baja | Documentar; preferir las mediciones nocturnas si se pueden identificar |
| 4.4 | **L** No usa la regularidad del sueño ni los eventos de salud | `RecoveryEngine` | Solo la duración principal | Contexto incompleto | Baja | Mostrar el evento de salud junto al puntaje, sin cambiar el cálculo |
| 4.5 | **R** El plan se ajusta con el puntaje agregado | `PlanAdvisor.lowRecovery` | La señal 1 de fatiga usa solo el valor total (mitigado: hacen falta 2 de 3 señales) | Una puntuación compuesta decide | Media | Usar los componentes (HRV de 7 días bajo la basal, FC alta) en lugar del total |

## 5. HealthScoreEngine 0.1-provisional

| # | Hallazgo | Archivo · función | Evidencia | Impacto | Prioridad | Corrección propuesta |
|---|---|---|---|---|---|---|
| 5.1 | **E** Usa el sueño total con siestas y noches incompletas | `HealthScoreEngine.sleep` | 23/10: salud 63 por 3,03 h de un registro incompleto (la recuperación ya lo excluye) | Inconsistente con la recuperación | Alta | Mismo criterio que la recuperación (sueño principal y noches incompletas fuera) |
| 5.2 | **R** Basal de media y DE con HRV de un solo día | `cardiovascular` | La recuperación usa mediana y MAD con 7 días en ln; aquí un valor atípico mueve la basal | Dos definiciones de «tu basal» | Media | Basal robusta (mediana/MAD) y la misma ventana de HRV |
| 5.3 | **L** Entradas correlacionadas | `exercise` y `balance` (minutos de ejercicio); `movement` (pasos) | No se cuenta dos veces la misma variable, pero ejercicio y equilibrio salen de la misma serie | Peso implícito mayor del ejercicio | Baja | Documentar |
| 5.4 | **L** Comparabilidad entre días | `evaluate` (reparte el peso cuando faltan dimensiones) | Un día sin HRV mide otra mezcla | — | Baja | Mostrar la cobertura junto al puntaje (ya existe en el detalle) |
| 5.5 | **C** Aviso no clínico | `ScoreDetailView` | «Estimación de bienestar, no una valoración clínica» | — | — | Añadir: «una puntuación alta no descarta una enfermedad» |

## 6. Calidad de datos

| # | Hallazgo | Evidencia | Clasificación | Propuesta |
|---|---|---|---|---|
| 6.1 | Cadencia imposible solo descarta la cadencia | `blocksPerformance` = falso | C | — |
| 6.2 | FC inválida no entra en las zonas ni en la intensidad | `heartRateUsable` en el clasificador y en la referencia | C | — |
| 6.3 | La FC máxima «observada» de Zonas no excluye entrenamientos marcados | `HeartRateZoneConfiguration.observedMax` solo filtra el rango plausible | R | Excluir `implausible_hr` y duplicados |
| 6.4 | Sin distancia no entra en ritmo ni forma | `missingDistance` bloquea | C | — |
| 6.5 | Cinta: política explícita | No elegible sin confirmar; un test confirmado en cinta, ×0,8 | C | — |
| 6.6 | Ausente ≠ 0 | El pulso 0 se exporta vacío; las series no rellenan | C | — |
| 6.7 | Siestas: no se suman dos veces | `sleep_h` las incluye y `nap_h` las detalla; la recuperación usa el sueño principal; la salud usa el total (ver 5.1) | R | — |
| 6.8 | Entradas fuera de orden | `DataQuality` ordena; la deduplicación de resultados no (1.5) | E | — |

## 7. Plan de la Fase B (para aprobar)

Prioridad alta, en este orden, con pruebas de regresión primero:

1. **2.1** Cumplimiento en semanas parciales (+ regla con pocos datos).
2. **1.3** Una sola definición de «tiempo de hoy».
3. **1.4 + 6.3** Referencia de FC máxima sobre datos deduplicados; el modelo siempre recibe entrenamientos limpios.
4. **5.1** La salud usa el mismo sueño que la recuperación.
5. **3.1** FC máxima configurada por debajo de la registrada: avisar y usar la observada.

Prioridad media: 1.5, 1.6, 1.8, 1.10, 2.5, 3.2, 3.3, 3.5, 4.1 (aportes en puntos), 4.5, 5.2.
Baja o solo documentación: 1.1 (doc), 1.7, 2.3, 2.4, 3.4, 4.2–4.4, 5.3–5.5.

Cambios de versión previstos: RacePerformanceModel 1.5 (1.4/1.5/1.8), proyección y
adherencia (2.1/2.5) dentro de 1.5, HealthScoreEngine 0.2 (5.1/5.2). RecoveryEngine solo
cambiaría con 4.2 o 4.5.
