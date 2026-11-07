# Recuperación estimada (VILA)

`RecoveryEngine` 0.2. Estimación orientativa del equilibrio entre esfuerzo y descanso. **No** indica si una persona está médicamente recuperada ni sustituye consejo profesional.

## Componentes

| Componente | Peso | Cálculo |
|---|---|---|
| HRV | 35 % | Media de los últimos 3 días con dato (mínimo 2) frente a tu línea basal robusta de los 28 días previos a esa ventana (mínimo 7). Un único valor no decide. |
| FC en reposo | 25 % | FC en reposo del día frente a tu línea basal robusta de 28 días (más baja = favorable). |
| Sueño | 25 % | El menor entre la curva de 7–9 h (la de HÄLSA) y la comparación con tu sueño habitual (mediana de 28 noches: sin penalización hasta 30 min por debajo, −25 puntos por hora más, mínimo 30). |
| Esfuerzo reciente | 15 % | Minutos de ejercicio de los 3 días anteriores frente a tu media de 28 días. |

### Curvas

- **Línea basal robusta** (0.2): mediana y MAD × 1,4826 en lugar de media y desviación típica; un valor raro no la mueve.
- **HRV y FC en reposo**: `z` = desviación favorable en desviaciones típicas robustas (HRV: mín. 5 % de la media o 1 ms; FC: mín. 2 lpm). En tu media = **75**; +2 → **100**; −3 → **15**, lineal por tramos. Un valor normal no es "100": deja margen para días mejores de lo habitual.
- **Esfuerzo reciente**: cociente ≤ 1 → **100**; 2,5 o más → **40**, lineal. Con una media habitual < 5 min/día el cociente no tiene sentido y el componente no se calcula.

## Reglas de cobertura

- Hace falta **HRV o FC en reposo** (al menos una señal fisiológica) y el **60 %** del peso con datos.
- Si aún no hay HRV o FC en reposo de hoy (por la mañana es habitual), se usa la de **ayer** y se indica; la confianza no puede ser alta.
- Confianza: alta (≥ 90 % de cobertura, ≥ 14 días de historial y valores de hoy), media (≥ 75 %), baja (resto).
- Sin datos suficientes se muestra "—" y el motivo; nunca se inventa.

## Sueño

- **Noche** = ventana de mediodía a mediodía (`SleepAggregator`); el total fusiona fuentes sin dobles conteos.
- **Fases** e hipnograma: solo de la fuente dominante, para no mezclar fases de apps distintas.
- **Tiempo dormido (%)**: tiempo dormido / tiempo entre dormirse y despertarse.
- **Regularidad**: media y desviación típica de las horas de dormirse y despertarse (mínimo 5 noches), medidas desde el mediodía anterior para no romperse a medianoche.
- **Objetivo**: elegido por el usuario (6–10 h, por defecto 8 h). La recomendación general para adultos es 7–9 h (Hirshkowitz et al., *Sleep Health* 2015; Watson et al., *Sleep* 2015).

## Uso en el plan

`PlanAdvisor` usa la recuperación como una de tres señales de fatiga (con el volumen y las sesiones exigentes): hacen falta **2 de los últimos 3 días** por debajo de max(50, tu mediana de 28 días − 15) y al menos otra señal para cambiar el plan. Un día bajo aislado no cambia nada.

## Pendiente

- Calibrar pesos y curvas con datos reales.
- Considerar frecuencia respiratoria y temperatura de muñeca cuando se verifique su disponibilidad.
