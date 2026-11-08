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

## Explicación del puntaje y sueño (0.10.0 (100))

- Cada componente guarda su valor reciente, su línea basal y los días de basal
  (`RecoveryComponent.recentValue`, `baselineValue`, `baselineDays`) y, para la
  HRV, la medición del día sin promediar. La pantalla «¿Por qué tengo este
  puntaje?» los muestra con su efecto, los datos que faltan y la confianza.
- Caso del 7 nov de 2026 (HRV 33,5 ms tras 49,8): la media de 3 días queda por
  encima de la basal; una caída aislada no baja el puntaje, tres días bajos sí.
- Sueño: episodios separados por ≥ 90 min; el principal fija el horario y las
  siestas se suman aparte (`napAsleep`). Avisos `SleepNightFlag` y patrón de
  28 noches (`SleepPattern`). Las fases del reloj no se usan para conclusiones.
- Eventos de salud (`HealthEvent`) se muestran como contexto sobre las
  tendencias, sin atribuir causas.

## RecoveryEngine 0.3 (0.10.0 (102))

- HRV: media móvil de 7 días de ln(SDNN) (mínimo 4 días; Plews et al. 2012,
  2013) frente a la línea basal en ln de los 28 días previos a la ventana.
  Sustituye a la media aritmética de 3 días de la 0.2. Historial necesario: 35 días.
- Sueño: solo el sueño principal (siestas aparte); un registro < 3 h cuando lo
  habitual son ≥ 5 h se considera incompleto y no se usa.
- Detalle y caso del 7/11 en `AUDITORIA_RPM_1_3.md`.

## RecoveryEngine 0.4 (0.10.0 (107))

- **Sin compensación total.** Valor = 0,75 × media ponderada + 0,25 × el componente más bajo. Una FC en reposo muy alta ya no queda tapada por un buen sueño. Por eso, en la línea basal con sueño y carga perfectos se obtiene 83 en lugar de 85, y en el caso real del 7/11, 80–81 en lugar de 83–84. Es intencional: una estimación prudente.
- **HRV alta no es automáticamente excelente.** El componente usa como mucho z = +1. Con z > 2 se avisa: puede ser normal o acompañar a cansancio acumulado (saturación parasimpática; Plews et al. 2012).
- **Enfermedad.** Con enfermedad, fiebre o lesión registradas para ese día, como mucho 50.
- **Sesión intensa reciente** (tempo o más, contada hasta las 8:00 del día). Es solo un aviso: no cambia el valor.
- **Avisos**: HRV inusualmente alta, enfermedad, sesión intensa, sueño incompleto, ventana de HRV corta, valor de ayer.
- **Explicación.** Incluye:
  - resumen;
  - factores a favor y en contra;
  - el cálculo con la media y el más bajo;
  - la comparación solo contigo;
  - la cobertura y la confianza;
  - los avisos.
- No es una medida clínica ni un diagnóstico.

### Sueño por episodios

- El sueño principal se atribuye al día en que te despiertas, y cada siesta al día en que empieza. La siesta del 7/11 (14:05–15:36, 1,52 h) cuenta para el 7, no para el 8.
- Los episodios posteriores a la hora del cálculo se ignoran: la recuperación de la mañana no usa una siesta de la tarde.
- Los duplicados entre fuentes se fusionan.
- La ventana de mediodía a mediodía se fija con el calendario, así que el cambio de hora no la desplaza.
