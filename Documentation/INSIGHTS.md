# INSIKT · análisis longitudinal

`InsightEngine` 0.1. INSIKT solo muestra una observación cuando hay **datos suficientes**, la diferencia supera un **contraste estadístico corregido por comparaciones múltiples** y el **efecto es relevante**. Si no, dice qué datos faltan. Nunca presenta una asociación como causa.

## Tipos de observación

| Tipo | Datos | Contraste | Umbral para mostrarse |
|---|---|---|---|
| **Lo que cambió** | Últimas 4 semanas frente a las 4 anteriores; ≥ 14 días con datos en cada una | t de Welch | q < 0,05 (Benjamini–Hochberg entre las 6 métricas) y \|d de Cohen\| ≥ 0,4 |
| **Patrones en tus datos** | Pares de días (180 días); ≥ 21 pares y ≥ 7 por grupo | Correlación de Spearman (p por aproximación t) | q < 0,05 (BH sobre los 6 pares de la lista, también los no evaluables) y \|ρ\| ≥ 0,25 |
| **Tu semana tipo** | Últimas 12 semanas; ≥ 4 valores de cada día de la semana | ANOVA de un factor | q < 0,05 (BH entre métricas) y diferencia máx.–mín. ≥ 0,5 desviaciones |
| **Récords** | Hasta 365 días y 300 entrenamientos | — | Pasos en un día, carrera más larga, ritmo más rápido (≥ 3 km), VO₂ máx. más alto, FC en reposo más baja (media de 7 días con ≥ 5 valores) |

Métricas de "Lo que cambió": FC en reposo, HRV, VO₂ máx., sueño, pasos, ejercicio. La dirección favorable (para el tono "En buena dirección" / "Conviene vigilarlo") es: FC en reposo más baja; HRV, VO₂ máx., pasos y ejercicio más altos; sueño más cerca de 7–9 h.

## Pares evaluados (lista cerrada)

No se buscan correlaciones entre todo con todo (eso produce casualidades). Solo pares con una relación fisiológica plausible y un orden temporal claro:

| Predictor | Resultado | Desfase |
|---|---|---|
| Sueño (noche que termina el día D) | HRV del día D | 0 |
| Sueño (noche que termina el día D) | FC en reposo del día D | 0 |
| Ejercicio del día D | HRV del día D+1 | 1 |
| Ejercicio del día D | FC en reposo del día D+1 | 1 |
| Ejercicio del día D | Sueño de la noche siguiente | 1 |
| Pasos del día D | Sueño de la noche siguiente | 1 |

Se describen con dos grupos (predictor por encima o por debajo de su mediana) y la media del resultado en cada uno, en lenguaje de **observación**: "Tras dormir 7 h 20 min o más, tu HRV fue de 64 ms de media; tras dormir menos, de 56 ms. … no prueba que una cosa cause la otra."

## Estadística

Implementación propia en `Stats` (sin dependencias) y verificada en tests con valores de tablas: t de Student (t = 2,228, 10 gl → p = 0,05), F (3,885 con 2 y 12 gl → p = 0,05), valor crítico de r (0,444 con n = 20 → p = 0,05), beta incompleta regularizada, rangos con empates, ejemplo de Benjamini–Hochberg.

## Modo demo

Los datos demo incluyen relaciones plausibles (más sueño ↔ más HRV y menos FC en reposo; mucho ejercicio → menos HRV al día siguiente; más pasos el fin de semana) para que se vean los patrones. Siempre se etiquetan como demo.

## Pendiente

- Reglas de recomendaciones accionables (con lenguaje no clínico) sobre estas observaciones.
- Revisar umbrales con datos reales de varios usuarios.
