# Auditoría de noviembre de 2026: diagnóstico y cambios

Lista «HÅLSYN — Mejoras y correcciones» (20 puntos), revisada con la exportación
real del 7 de noviembre de 2026. Todo sigue siendo local, determinístico y sin
servicios externos. Para cada punto: qué existía, qué se cambió y por qué.

## Prioridad 1 — Running y predicciones

| # | Existía | Cambio |
|---|---------|--------|
| 1 VDOT | Media ponderada tipo × antigüedad; entrenamientos solo suben. | Peso = tipo × antigüedad × **distancia** (< 1,5 km 0,6; 1,5–3 km 0,85) × **calidad** (cinta 0,8; FC media < 85 % de la máxima 0,7) × **tope** (los entrenamientos suman como mucho la mitad del peso de los tests) × coherencia. Cada prueba guarda sus factores y el valor que entra en la media. La pantalla y la exportación dicen si el VDOT sale de **una prueba** o de una **media ponderada**. |
| 1 · 33,7 vs 34,4 | El resumen atribuía el VDOT combinado al test más reciente. | 34,4 = (35,1 × 0,80 + 33,7 × 0,83) ÷ 1,63: media ponderada de los tests del 31 oct y del 2 nov. Ahora se muestra así, con la fórmula. |
| 2 Duplicados | Mismo día, tiempo ≤ 2 %, distancia ≤ 3 %; entrenamientos de Salud por hora/duración/distancia/superposición. | Además, **mismo identificador de Salud = duplicado siempre**. Corrección manual «no es un duplicado» (y deshacerla). Los registros originales siguen visibles con su papel. Caso 31 oct (3,00 y 3,03 km, 15:51) cubierto por pruebas. |
| 3 Hoy vs proyección | Ya separados (Fase de octubre). | Sin cambios de cálculo; la explicación muestra ambos y la mejora esperada. |
| 4 Rangos | Inflados por n efectivo (Kish), horizonte y día de carrera. | Textos: «orientativo, pensado como 80 %, sin validar»; nunca se afirma cobertura sin datos. |
| 5 Validación retrospectiva | Backtest sin datos futuros, MAE/RMSE/sesgo/cobertura, n mínimo 5. | Sin cambios; prueba de no filtración existente. |

## Prioridad 2 — Entrenamientos y plan

| # | Existía | Cambio |
|---|---------|--------|
| 6 Cumplimiento | Hechas/programadas y frecuencia por días. | «3 / 3 · 100 %»; parciales, no hechas y **no hechas por enfermedad o lesión (no cuentan)** por separado; frecuencia aparte. |
| 7 Intensidad | Suave/moderado/fuerte/a tope por FC media. | `IntensityClassifier`: recuperación, suave, moderado, tempo/umbral, series (oscilación del pulso o sesión de series del plan), a tope, test, competición. Sin pulso: ritmo frente al umbral (aproximado) o esfuerzo percibido; **nunca «a tope» sin pulso**. |
| 8 Carga | TRIMP/TSS, CTL/ATL, monotonía. | `TrainingVolumeAnalysis`: km por semana, medias 4/8/12, tendencia Theil–Sen, minutos por intensidad, otras actividades, días de descanso, rachas, días intensos seguidos y aumento brusco **frente a tu propio historial** (media de 4 semanas + 2 DE de 8, mínimo +25 % y +3 km). No predice lesiones. |
| 9 Adaptación | Molestias, fatiga 2 de 3, nunca dos exigentes seguidas. | Motivo de sesión no hecha (enfermedad, lesión, viaje, tiempo, otro). Eventos de salud: vuelta gradual (sin exigentes, larga al 80 %; descanso 2 días con fiebre/lesión en curso). **Ningún ajuste sube distancia o intensidad para compensar.** |
| 10 Simulador | Existía (conservador/central/optimista). | Sin cambios. |

## Prioridad 3 — Salud

| # | Existía | Cambio |
|---|---------|--------|
| 11 Recuperación | Línea basal robusta, HRV media de 3 días. | **Caso 7 nov**: HRV del día 33,5 ms frente a 49,8 ayer, pero media de 3 días ≈ 44,1 ms frente a una basal ≈ 32 ms → componente positivo; FC 62 frente a ≈ 65; sueño 6,9 h frente a ≈ 6,3 h habituales. El 91 está justificado por el diseño (una caída aislada no baja el puntaje; tres días bajos sí — prueba incluida). Ahora se explica en pantalla. |
| 12 ¿Por qué este puntaje? | Desglose de componentes sin valores. | Pantalla con variables, peso, valor reciente y basal (días de basal), efecto, datos que faltan, confianza, versión y aviso no clínico. En HÄLSA, el detalle existente pasa a titularse así. |
| 13 Eventos de salud | No existía. | Registro con tipo, nombre, inicio, fin y nota. Bandas sobre los gráficos (recuperación, HRV, FC en reposo, detalle de métricas) y texto de contexto sin atribuir causas. Usado por la adherencia y el plan. |
| 14 Sueño | Noche de mediodía a mediodía, fuentes fusionadas. | Episodios separados por ≥ 90 min: el **sueño principal** fija el horario; las siestas se suman al total pero aparte (caso 3 nov, siesta 15:36). Avisos: siesta sumada, registro corto (< 3 h), fragmentado, varias fuentes. Patrón: medias 7/28, variación del punto medio, tendencia, noches cortas repetidas y horarios atípicos. Las fases no se usan para conclusiones. |
| 15 Cardiometabólico | No existía. | Presión, glucemia, HbA1c, lípidos, peso y otros, con unidad (mg/dL o mmol/L), fecha, tendencia y referencia general con fuente (ESC 2024, AHA/ACC 2017, ADA 2025, ESC/EAS 2019). No diagnostica ni toca puntuaciones. |

## Prioridad 4 — Datos y experiencia

| # | Cambio |
|---|--------|
| 16 Validación | Ya se marcaban FC 0, sin distancia, cortos, ritmos/cadencias imposibles y superposiciones entre fuentes. Ahora la exportación deja **vacío** (no 0) un pulso de 0. |
| 17 ¿Por qué este tiempo? | Pantalla con la fórmula real de la media, pruebas usadas y descartadas con motivo, factores de cada peso, tiempo hoy, mejora proyectada y límites. |
| 18 Exportación | Versión de cada algoritmo y del formato, fecha de cálculo, fuentes, `record_id` (hash FNV-1a corto), columnas calculadas listadas, calidad de datos, CSV de pruebas con factores, eventos y laboratorio. Columnas nuevas siempre al final (compatibles). |
| 19 Gráficos | Volumen e intensidad semanal (barras apiladas), evolución del objetivo (hoy frente a proyectado y objetivo), eventos sobre las tendencias. VDOT con pruebas, HRV/FC y sueño/recuperación ya existían. |
| 20 Pruebas | `NovemberAuditTests`, `IntensityAndVolumeTests`, `HealthAuditTests`: duplicados, pesos, tests más lentos, rodajes, cumplimiento, enfermedad, intensidad, volumen, recuperación con datos reales, sueño con siesta, laboratorio y exportación. Fixtures anonimizados (sin nombres, zapatillas ni identificadores). |
