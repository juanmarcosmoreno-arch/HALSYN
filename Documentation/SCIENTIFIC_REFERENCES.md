# Referencias científicas

## Política

- **No se inventan datasets ni percentiles.** Ninguna comparación poblacional se mostrará sin una fuente verificada con los campos de la plantilla.
- Se distinguen valores medidos directamente (laboratorio) de estimaciones del Apple Watch; no se comparan entre sí sin advertirlo.
- Las puntuaciones de HÅLSYN son estimaciones de bienestar, no medidas clínicamente validadas.

## Estado (Fase 1)

No hay ningún dataset incorporado. Los valores del modo demo son sintéticos, plausibles para un adulto activo, y **no** constituyen referencias.

## Referencias usadas como umbrales en HealthScoreEngine (Fase 3)

Orientan los umbrales; **no validan** la puntuación de HÅLSYN en conjunto.

| Uso | Referencia | Qué se toma |
|---|---|---|
| Sueño 7–9 h (adultos) | Watson NF, et al. *Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the American Academy of Sleep Medicine and Sleep Research Society.* Sleep. 2015;38(6):843–844. | ≥ 7 h por noche de forma regular en adultos; el rango 7–9 h se usa como referencia de máxima puntuación. |
| 150 min/semana de actividad | Bull FC, et al. *World Health Organization 2020 guidelines on physical activity and sedentary behaviour.* Br J Sports Med. 2020;54(24):1451–1462. | 150–300 min/semana de actividad moderada (o equivalente) en adultos. Se usan los "minutos de ejercicio" de Apple como aproximación. |
| 8.000 pasos/día | Paluch AE, et al. *Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts.* Lancet Public Health. 2022;7(3):e219–e228. | El beneficio se estabiliza aproximadamente entre 6.000–8.000 pasos (≥ 60 años) y 8.000–10.000 (< 60 años); 8.000 se usa como referencia única provisional. |
| Carga aguda:crónica | Gabbett TJ. *The training—injury prevention paradox: should athletes be training smarter and harder?* Br J Sports Med. 2016;50(5):273–280. | Concepto de comparar carga reciente con habitual; zona 0,8–1,3. |
| Críticas al cociente | Impellizzeri FM, et al. *Acute:Chronic Workload Ratio: Conceptual Issues and Fundamental Pitfalls.* Int J Sports Physiol Perform. 2020;15(6):907–913. | Motivo del peso bajo (15 %) y de no tratarlo como predictor de lesiones. |
| HRV y FC en reposo frente a la media personal | Práctica habitual de comparar con la línea basal individual en lugar de valores poblacionales, dada la gran variabilidad entre personas. | Comparación con la media de 28 días; sin percentiles poblacionales (Fase 8). |

Pendiente: revisar cada cita con su texto completo antes de la publicación y registrar DOI/PMID.

## Fuentes a investigar (Fase 8)

- NHANES (CDC) — encuestas poblacionales de EE. UU.
- FRIEND Registry — capacidad cardiorrespiratoria medida en prueba de esfuerzo.
- Literatura indexada en PubMed sobre FC en reposo y HRV por edad y sexo.
- Recomendaciones oficiales de actividad física y sueño (OMS y sociedades científicas).

Cada candidata se revisará por: población, método de medición, compatibilidad con la estimación del Apple Watch y licencia de uso.

## Plantilla de dataset

```yaml
id:
fuente:            # publicación u organismo
referencia:        # DOI / PMID / URL oficial
año:
población:
país:
rango_edad:
sexo:
método_medición:   # p. ej. prueba de esfuerzo con análisis de gases
unidad:
tamaño_muestra:
percentiles:       # por grupo de edad/sexo
limitaciones:
compatible_con_apple_watch:   # sí / con advertencia / no, y por qué
```

## Edad fisiológica

Arquitectura prevista, pero **sin fórmula** hasta disponer de un modelo validado aplicable a los datos del Apple Watch. Mientras tanto solo se mostrarán indicadores y percentiles.

## Zonas cardíacas (Fase 5)

- **Método de la reserva cardíaca**: Karvonen MJ, Kentala E, Mustala O. *The effects of training on heart rate; a longitudinal study.* Ann Med Exp Biol Fenn. 1957;35(3):307–315. Intensidad = FC reposo + (FC máx − FC reposo) × fracción.
- **Modelo de 5 zonas (50/60/70/80/90 %)**: convención extendida en entrenamiento de resistencia y en dispositivos deportivos; **no** es un estándar clínico. Las guías del ACSM (*ACSM's Guidelines for Exercise Testing and Prescription*) describen la intensidad por % de FC máx. y % de reserva con rangos parecidos, pero sus categorías no coinciden exactamente con estas 5 zonas.
- **FC máxima**: HÅLSYN **no la estima por la edad** (las fórmulas tipo 220 − edad tienen un error individual grande). Solo usa un valor introducido por el usuario o el máximo registrado en sus carreras, y lo dice.
- La interfaz presenta las zonas como guía de entrenamiento, nunca como indicación médica.
