# Puntuación diaria de HÄLSA (`HealthScoreEngine`)

> **Es una estimación de bienestar y hábitos, no una valoración clínica.** La puntuación no está validada en estudios. Los umbrales se apoyan en recomendaciones públicas (ver [SCIENTIFIC_REFERENCES](SCIENTIFIC_REFERENCES.md)), pero su combinación es una hipótesis de producto. Versión actual: `0.1-provisional`.

Código: `Packages/HalsynKit/Sources/HalsynCore/Engines/HealthScoreEngine.swift`. Tests: `HealthScoreEngineTests.swift`.

## Dimensiones y pesos

| Dimensión | Peso provisional | Datos | Regla |
|---|---|---|---|
| Sueño | 25 % | Horas dormidas la noche que termina ese día | 100 entre 7 y 9 h. Por debajo de 7 h baja linealmente hasta 0 a las 4 h. Por encima de 9 h baja suavemente hasta un mínimo de 70. |
| Estado cardiovascular | 25 % | FC en reposo y HRV de ese día frente a tu media de los 28 días anteriores (mínimo 7 días) | Desviación desfavorable en desviaciones típicas (`z`): hasta 1 → 100; de 1 a 3 → de 100 a 40; más de 3 → 40. Para la FC en reposo lo desfavorable es subir; para la HRV, bajar. **Estar "mejor" que tu media no suma más.** FC en reposo y HRV se **promedian** (no se suman) para no contar dos veces la misma señal. Desviación típica mínima: 2 lpm para la FC en reposo y el 5 % de la media para la HRV. |
| Movimiento | 20 % | Media de pasos de los **7 días completos anteriores** (mínimo 4 días con dato) | Proporcional hasta la referencia de tu edad (Paluch et al., 2022): 9.000 pasos/día antes de los 60 años, 7.000 a partir de los 60 y 8.000 sin edad conocida; a partir de ahí, 100 (más pasos no suman). |
| Ejercicio | 15 % | Minutos de ejercicio de los **7 días completos anteriores** | Proporcional hasta 150 min/semana. Al ser semanal, **un día de descanso no penaliza**. |
| Equilibrio esfuerzo-recuperación | 15 % | Carga aguda (media de 7 días) frente a crónica (media de 28 días) con minutos de ejercicio; requiere ≥ 14 días y ≥ 5 min/día de media | 100 entre 0,8 y 1,3. Por encima baja hasta 40 en 2,0 (aumento brusco de carga). Por debajo solo baja hasta 70 en 0,3 (una semana más tranquila no es un problema). |

Los pesos están en `HealthScoreWeights` y se pueden cambiar sin tocar el motor.

### Por qué días completos

Movimiento y ejercicio usan los 7 días **anteriores** a hoy. Así la puntuación de hoy no baja por consultar la app a las 9:00 con pocos pasos todavía, y no "premia" moverse más tarde en el día. Sueño y estado cardiovascular sí son de hoy: se miden por la noche y por la mañana.

## Combinación

1. Cada dimensión da 0–100 o "sin dato" (`noData`) / "necesita historial" (`insufficientHistory`).
2. **Cobertura** = peso de las dimensiones con dato ÷ peso total.
3. Si la cobertura es **≥ 60 %**, la puntuación es la media ponderada de las dimensiones disponibles (los pesos se **renormalizan**; una dimensión sin dato no cuenta como 0). Si no, no hay puntuación.
4. **Confianza**: alta (cobertura ≥ 90 % y ≥ 14 días de referencia cardiovascular), media (cobertura ≥ 75 %), baja (resto).
5. **Variación semanal**: puntuación de hoy menos la media de las puntuaciones de los 7 días anteriores (si hay al menos 3).

## Explicaciones

El motor devuelve factores estructurados (`ScoreFactor`) con su impacto (favorable, neutro, desfavorable). La app los traduce a frases como "FC en reposo 6 lpm por encima de tu media" o "Media de 8.500 pasos al día en los últimos 7 días". Los desfavorables se muestran primero.

## Resumen del día (`DailySummaryComposer`)

Frases generadas solo con datos disponibles:

| Frase | Regla |
|---|---|
| Valoración general | Banda de la puntuación del día, si existe |
| Actividad | Pasos de hoy frente a tu media de 28 días (mínimo 7): ±15 % = "dentro de tu promedio" |
| FC en reposo | Frente a tu rango habitual (`z` entre −1 y 1 = "dentro") |
| Sueño | Horas de anoche y si están en 7–9 h |
| Ejercicio | Minutos de los últimos 7 días (incluido hoy) frente a 150 |

La notificación nocturna es opcional (Perfil › Resumen nocturno), a la hora que elijas, y **no incluye datos de salud** en el aviso: el resumen se calcula al abrir la app.

## Demo y datos reales

`computeDailyScores` (extensión de `HealthDataProviding`) obtiene las series del proveedor y aplica el motor. El modo demo y Apple Health usan **exactamente las mismas reglas**; el origen se muestra como "Datos demo" o "Calculado por HealthScoreEngine".

## Limitaciones conocidas

- Pesos y umbrales no están calibrados con datos de usuarios ni validados frente a resultados de salud.
- La carga usa minutos de ejercicio como aproximación; `TrainingLoadEngine` (TRIMP / sRPE) la sustituirá en la Fase 5. El cociente agudo:crónico tiene críticas metodológicas (ver referencias): aquí solo pesa un 15 % y apenas penaliza la carga baja.
- La regularidad del sueño y las fases no se valoran todavía (Fase 6, VILA).
- La FC en reposo y la HRV del Apple Watch son estimaciones del dispositivo; su precisión depende del modelo y del ajuste del reloj.
- No hay ajuste por edad, sexo, enfermedad, medicación, altitud, alcohol o ciclo menstrual.
