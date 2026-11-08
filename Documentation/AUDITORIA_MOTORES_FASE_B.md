# Auditoría técnica de los motores — Fase B (correcciones)

Hallazgos de `AUDITORIA_MOTORES_FASE_A.md` corregidos en 0.10.0 (106).
Versiones: **RacePerformanceModel 1.5**, **HealthScoreEngine 0.2-provisional**,
RecoveryEngine 0.3 (sin cambios de cálculo), exportación formato 3 (una
columna nueva al final). Pruebas: 483 (21 nuevas en `EngineAuditPhaseBTests`).

## Cambios, motivo y resultado antes → después (caso real del 7/11/2026)

| # | Qué cambió | Por qué | Antes → después |
|---|---|---|---|
| 2.1 | Frecuencia = días con carrera ÷ sesiones programadas **en los días transcurridos** (sin las excusadas); con pocos datos (< 2 semanas o < 4 sesiones) el cumplimiento para la proyección se mezcla con el supuesto central: (n × observado + 4 × 0,85) ÷ (n + 4) | Una semana a medias (5 días) se comparaba con 4 carreras por semana sin normalizar | Factor 0,70 → **1,00**; mejora 0,92 → **1,25 VDOT**; 5 km el 18/1: 26:46 → **≈ 26:34** (26:48 → 26:36 con el fixture) |
| 1.3 | «Hoy» = tiempo de Daniels con el VDOT actual en todas las vistas; Riegel queda como comprobación y ensancha el rango si difiere | La tarjeta de Predicción (media con Riegel) y «Tu objetivo» daban tiempos distintos | Predicción 27:29 → **27:24**, igual que «Tu objetivo» y la exportación |
| 1.4 · 6.3 | La FC máxima de referencia y la observada se calculan sin duplicados ni pulso inválido; el modelo recibe siempre las carreras limpias, también desde la exportación, la carga y la validación | Con un entrenamiento reimportado, la referencia pasaba de 186 a 189 y el 1/11 dejaba de ser candidato | Con y sin reimportación: referencia 186, mismo VDOT y mismas pruebas |
| 1.4 b | Un entrenamiento equivalente a un resultado registrado no se usa también como esfuerzo de entrenamiento | La copia de un test marcado podía contarse dos veces | La copia queda fuera |
| 3.1 | Si la FC máxima configurada queda más de 2 lpm por debajo de la referencia observada, el modelo y la intensidad usan la observada y se avisa (en Ajustes › Zonas y en la exportación) | Una máxima demasiado baja hace parecer muy intensos los rodajes | Con 184 configurada y 186 observada la diferencia está dentro de la tolerancia (no cambia); con 180, se usaría 186 |
| 5.1 | El sueño de la puntuación de salud es el sueño principal; una noche incompleta no se usa | La salud penalizaba noches que la recuperación ya excluía | 23/10: deja de contar las 3,03 h de un registro incompleto |
| 5.2 | Puntuación de salud: basal robusta (mediana/MAD) y HRV media de 7 días en ln, como la recuperación | Dos definiciones de «tu basal»; un valor atípico movía la de la salud | Un día atípico ya no cambia el puntaje cardiovascular |
| 1.5 | Deduplicación con orden total (de entrenamiento > más antiguo > id) | El resultado dependía del orden de entrada | Igual en cualquier orden; idempotente |
| 1.6 | Al marcar un entrenamiento como test ya no se borra el resultado manual equivalente | Trazabilidad | Se conservan los dos; cuenta uno |
| 1.7 | Duplicados también a ±12 h (no solo el mismo día de calendario) | Test a las 23:50 cargado a mano «al día siguiente» | Detectado |
| 1.8 | Una sesión de umbral o de series planificada no es candidata para el VDOT (confirmable a mano) | Un umbral a tope no es una prueba | Nuevo motivo `not_eligible:plannedWorkout` |
| 1.10 | La validación retrospectiva usa los mismos parámetros que el modelo en vivo | Medía otro modelo | — |
| 2.5 | Los días de enfermedad o lesión **con fecha de fin** por delante se restan de las semanas efectivas | La proyección no tenía en cuenta una baja conocida | 14 días → −2 semanas |
| 3.2 | Con zonas por FC de umbral, la intensidad usa las zonas de Friel (% de la FC de umbral) | La intensidad no coincidía con las zonas elegidas | Solo si el método es «umbral» |
| 3.3 | Aviso «Planificada como … , hecha como …» en el detalle y columna `harder_than_planned` en la exportación; no cambia el objetivo de la sesión | Faltaba explicar la discrepancia | 6 y 7/11 marcados si la intensidad fue alta |
| 3.5 | La exportación clasifica con el pulso segundo a segundo de las últimas 6 semanas | Sin muestras no se detectaban series | Igual que la pantalla |
| 4.1 | «¿Por qué tengo este puntaje?» muestra el aporte en puntos de cada componente frente a la base de 75 | Explicabilidad | 7/11: HRV +1,1 · FC +3,5 · sueño +5,3 · carga −0,5 |
| 4.5 | El plan solo cuenta un día de recuperación baja si además la HRV o la FC en reposo están peor que tu basal | El puntaje agregado solo no debe decidir | — |
| 5.5 | «Una puntuación alta no descarta una enfermedad» | No aparentar valor clínico | — |

## Sin cambios (correcto o limitación documentada)

- Ecuaciones de Daniels–Gilbert, VDOT combinado 34,3439 a precisión completa,
  pesos por antigüedad (0,8909 y 0,9208) y fórmula de mejora: correctos.
- Limitaciones que se mantienen documentadas: afinamiento restado y semanas de
  descarga no (2.3); cumplimiento → factor lineal 40–90 %, supuesto de HÅLSYN
  (2.4); carga de la recuperación por minutos de ejercicio (4.2); HRV SDNN
  promedio del día (4.3); entradas correlacionadas en la salud (5.3).
- Intervalos: siguen siendo orientativos; se calibran con `PredictionBacktest`
  (n ≥ 5: error medio, sesgo, cobertura) y `GoalCalibration` (Brier) cuando
  haya resultados reales.
