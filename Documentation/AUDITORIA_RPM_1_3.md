# Informe técnico: auditoría posterior a RacePerformanceModel 1.3

Versiones resultantes: **RacePerformanceModel 1.4**, **RecoveryEngine 0.3**,
formato de exportación 3 (columnas nuevas al final). Todo local, determinístico
y reproducible. Los casos se reprodujeron con las carreras y los datos diarios
de la exportación del 7/11/2026, ya incorporados como fixture en las pruebas
(`NovemberFixture`, `HealthAuditTests`, `ModelAuditTests`).

> La exportación de las 21:01 no estaba disponible en el entorno de trabajo;
> se usó la de las 19:07 del mismo día (mismas carreras y tests). Cuando una
> cifra depende de un dato que cambió entre ambas (pulso en reposo 60 frente a
> 62), se calculan las dos.

## 1. Criterio «below_estimate»

**Causa.** El modelo trataba igual cualquier entrenamiento detectado como «a
tope»: si estaba por debajo de la forma, no contaba. Los tests confirmados ya
contaban siempre (también más lentos), pero no había forma de confirmar un
entrenamiento, y la etiqueta no distinguía un esfuerzo probable de un rodaje.

**Cambio.**
- Tres niveles de elegibilidad para el VDOT (`VDOTEligibility`): **confirmado**
  (test o competición marcados: cuentan siempre, en las dos direcciones),
  **candidato** (cumple los criterios del punto 2; solo puede subir la
  estimación) y **no elegible** con su motivo.
- Un candidato que queda **más de 3 puntos** por debajo de los tests pasa a
  `not_maximal`: si hubiera sido a tope implicaría perder un 10 % de forma en
  días. Entre 0 y 3 puntos por debajo queda como `unconfirmed_below_estimate`.
- Se puede confirmar («Fue a tope: usarlo como test») o descartar («No fue a
  tope») desde la predicción y desde el detalle del entrenamiento.

**Caso real.** El 1/11 (4,00 km, 22:25, FC 170) es candidato con VDOT 33,1 frente
a 34,3: no confirmado, no baja la forma. Si lo confirmas como test, la baja
(prueba `confirmedSlowerEffortLowersTheEstimate`).

## 2. «max_effort»

**Causa principal (error).** La FC máxima de referencia para decidir si un
entrenamiento fue a tope se calculaba **solo con las carreras al aire libre**
(segunda más alta: 182 lpm) en lugar de con todas (186 lpm, cinta incluida).
Con 182, los rodajes del 6/11 (166 lpm, 65 m de desnivel en 3 km) y del 7/11
(166 lpm, 6 km en 36:51) quedaban en el 91 % y pasaban por esfuerzos máximos.

**Cambio.** Se separan tres cosas:
- **Intensidad fisiológica** (`intensity`): por pulso. «max_effort» pasa a
  `very_hard` (FC media ≥ 90 % sostenida ≥ 8 min): describe la intensidad, no
  dice que fuera un test.
- **Tipo de sesión** (`session_type`): la del plan ese día o la estructura
  detectada (series).
- **Elegibilidad para el VDOT** (`vdot_eligibility`): FC media ≥ 90 % de la
  máxima de referencia (de todas las carreras) y ≥ FC de umbral si la
  configuraste; 8–75 min; ≥ 3 km; al aire libre; ≤ 10 m de desnivel por km;
  sin sesión suave, larga o de recuperación planificada ese día; datos válidos;
  no descartado por ti.

## 3. Duplicados en la exportación

**Causa.** El resumen listaba los dos resultados del 31/10 (3,00 km cargado a
mano y 3,03 km del entrenamiento), pero el CSV de entrenamientos tiene una fila
por **entrenamiento** de Salud: el resultado manual no tiene entrenamiento y no
aparecía en ningún CSV.

**Cambio.** Nuevo `halsyn-resultados-AAAA-MM-DD.csv` con **todos** los
resultados (también duplicados): origen (`manual` o `workout`), `record_id`,
`workout_record_id` (el `record_id` de la fila del CSV de entrenamientos),
`status` (`used`/`duplicate`), `duplicate_of` y `marked_distinct`. El CSV de
pruebas añade `workout_record_id` y `duplicate_of`, y el resumen muestra los
mismos códigos.

## 4. RecoveryEngine: el 92 del 7/11

**Cálculo con 0.2** (HRV 33,5 ms, FC 60–62 lpm, sueño 6,87 h):

| Componente | Peso | Valor usado | Basal (mediana) | Puntos |
|---|---|---|---|---|
| HRV | 35 % | media de 3 días = (49,0 + 49,8 + 33,5) / 3 = 44,1 ms | ≈ 32 ms | ≈ 96 |
| FC en reposo | 25 % | 62 (60) lpm | 65 lpm | 83 (89) |
| Sueño | 25 % | 6,87 h | habitual 6,4 h | 96 |
| Esfuerzo reciente | 15 % | 37 min/día (3 días) | 22 min/día (28 días) → ×1,70 | 72 |

≈ 0,35·96 + 0,25·83 + 0,25·96 + 0,15·72 ≈ 88–90; con el pulso de la exportación
de las 21:01 y el redondeo de cada componente, 91–92.

**Causa.** La media de **3 días** era una elección propia de HÅLSYN: dos días
altos (49,0 y 49,8) tapaban un día normal y hacían que la HRV sumara de más.
La práctica documentada (Plews et al. 2012, 2013) es la **media móvil de 7
días del logaritmo** de la HRV frente a la línea basal personal.

**Cambio (0.3).**
- HRV: media de 7 días de ln(SDNN) (mínimo 4 días con dato; si no, baja la
  confianza), frente a la mediana y la MAD de ln en los 28 días previos a la
  ventana. Se muestra la medición del día, los días con dato de la ventana y la
  tendencia frente a la semana anterior.
- Se corrigió que el historial pedido a Salud no alcanzara para 28 días de
  basal con la ventana de 7 (`historyDaysNeeded` = 35).
- Sueño: ver el punto 10.

**Resultado 0.3 para el 7/11:** HRV 34,2 ms (media geométrica de 7 días)
frente a 32,9 ms → neutral, 78 puntos; FC 83 (89 con 60 lpm); sueño 96;
esfuerzo 72. **Recuperación 83 (84 con 60 lpm)**, confianza alta. Una caída
mantenida de 3 días sigue bajándola (prueba `sustainedHRVDropDoesLowerIt`).
SDNN no es RMSSD (la medida de Plews): la ventana se adopta por su lógica
estadística y se documenta la diferencia.

## 5. Proyección del 18/01/2027

Con la pauta central (prueba `projectionArithmetic`):

1. Forma de hoy: VDOT 34,34 → 5 km en 27:24 (Daniels). (La exportación decía
   27:22: los datos del día cambiaron un poco entre una y otra.)
2. Semanas de entrenamiento antes del afinamiento: **9**.
3. Ritmo de mejora: **1/6 VDOT por semana** (pauta de Daniels; tu tendencia
   todavía no se usa: hacen falta 3 tests en 3 semanas o más).
4. Cumplimiento efectivo = mín(3/3 sesiones, 3 ÷ 4 carreras por semana) =
   **75 %** → factor (0,75 − 0,4) ÷ 0,5 = **0,70**. Frecuencia del plan (4/semana) → 1.
5. Mejora = 4 × (1 − e^(−9 × 1/6 × 0,70 ÷ 4)) = **0,92 VDOT** (rendimientos
   decrecientes, tope de 4 puntos).
6. VDOT el día de la carrera 35,27 → **26:48**.
7. Rango ±1,28 σ con σ = √(0,98² + (½·0,92)² + (0,15·√9)² + 0,7²) = 1,37 VDOT:
   25:44–27:58, **orientativo**: el rango no está calibrado y se rotula así en la
   pantalla y la exportación hasta que haya resultados para validarlo.

## 6. Clasificación de las sesiones recientes (FC máx. de referencia 186)

| Fecha | km | FC media (% máx.) | Intensidad | VDOT |
|---|---|---|---|---|
| 28/10 | 0,27 | 0 (sin dato) | sin clasificar | no elegible: datos |
| 29/10 | 2,04 | 160 (86 %) | moderado | no: < 3 km |
| 31/10 | 3,03 | 176 (95 %) | muy intenso | **test confirmado** |
| 1/11 | 4,00 | 170 (91 %) | muy intenso | candidato, por debajo, sin confirmar |
| 2/11 | 4,00 | 171 (92 %) | muy intenso | **test confirmado** |
| 4/11 | 5,03 | 161 (87 %) | moderado | no: pulso < 90 % |
| 6/11 | 3,04 | 166 (89 %) | tempo | no: pulso < 90 % (con 184: mucho desnivel) |
| 7/11 | 6,02 | 166 (89 %) | tempo | no: pulso < 90 % (con 184: no fue a tope) |

## 7–8. Interfaz

En «¿Por qué HÅLSYN estima este tiempo?» cada prueba muestra su peso, sus
factores y el motivo concreto de inclusión o exclusión. Mantener pulsada una
prueba candidata permite confirmarla como test o descartarla; las descartadas
se listan con «Volver a considerarlo». En el detalle de cada carrera se ve la
intensidad, con qué se decidió y si sirve para el VDOT (con el motivo).

## 10. Sueño

- Siestas: el sueño principal es el tramo con más sueño (separación de 90 min
  o más); la siesta se suma al total del día pero **no** al «sueño de anoche»
  de la recuperación (3/11: 7,2 h de noche, 1,5 h de siesta aparte).
- Noches incompletas: un registro de menos de 3 h cuando lo habitual son 5 h o
  más (23/10: 3,0 h, 19:00–22:12) se marca y **no** entra en la recuperación
  (antes la hundía a 48); la confianza baja por el dato que falta.
- Fragmentación: más del 20 % despierto en el sueño principal o 3 tramos o más.

## 9. Pruebas

460 pruebas, todas en verde. Nuevas: `ModelAuditTests` (elegibilidad,
referencia de FC máxima, `not_maximal`, confirmación y descarte, trazabilidad de
duplicados en CSV, aritmética de la proyección, historial de 35 días, siestas y
noches incompletas en la recuperación) y la regresión del 7/11 en
`HealthAuditTests` (83 con 0.3). Se ajustaron tres pruebas previas al nuevo
criterio, documentando el porqué en cada una.

## Referencias

- Plews DJ, Laursen PB, Kilding AE, Buchheit M. *Heart rate variability in
  elite triathletes: is variation in variability the key to effective training?*
  Eur J Appl Physiol 2012. — y — *Training adaptation and heart rate
  variability in elite endurance athletes: opening the door to effective
  monitoring.* Sports Med 2013. Por qué: media móvil de 7 días de ln-HRV en
  lugar de valores diarios aislados.
- Daniels J. *Daniels' Running Formula*. Por qué: VDOT y pauta de mejora.
