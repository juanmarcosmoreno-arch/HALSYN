# Motor de running (SPRING)

## Estado actual (Fase 1)

Implementado y probado en `HalsynCore`:

- `Pace`: ritmo en s/km, conversión desde distancia+duración o velocidad, formato `m:ss`, unidades métricas e imperiales, descarte de ritmos no válidos (< 10 m, > 60 min/km).
- `WorkoutSummary`: resumen de entrenamiento con campos opcionales (nunca se rellenan si el reloj no los midió).
- `WorkoutFieldKind`, `WorkoutScreenLayout` (1, 2, 3, 4, 6 campos) y `WorkoutScreenProfile` con perfiles **Easy Run**, **Intervals** y **Race**; validación y serialización JSON.
- `HalsynWorkoutScreen` (UI) y vista previa en iPhone y reloj con `DemoWorkoutSample` (valores de ejemplo).

**No existe todavía ninguna sesión de entrenamiento.** El reloj no registra ni guarda carreras.

## Diseño previsto (Fase 4 — prioridad muy alta)

```
WorkoutSessionController (watchOS)
 ├─ HKWorkoutSession + HKLiveWorkoutBuilder   ← estado, FC, energía, distancia
 ├─ CLLocationManager → HKWorkoutRouteBuilder ← ruta y distancia GPS
 ├─ PaceEstimator (Core, puro, testeable)      ← instantáneo / suavizado / medio / vuelta
 ├─ LapTracker, HeartRateZoneCalculator (Core)
 └─ estado publicado → HalsynWorkoutScreen
```

- Estados: `idle → prepared → running ⇄ paused → ended → saved / discarded`; transiciones validadas en un tipo puro con tests.
- Recuperación tras interrupción: `HKHealthStore.recoverActiveWorkoutSession` (verificar en watchOS objetivo).
- Duplicados: un único builder por sesión; el iPhone no escribe entrenamientos creados en el reloj.
- Requiere `WKBackgroundModes = workout-processing` y textos de ubicación (se añadirán en Fase 4).

### Ritmo y GPS (propuesta a validar con datos reales)

- Descartar ubicaciones con `horizontalAccuracy` > umbral y saltos físicamente imposibles.
- Ritmo instantáneo a partir de velocidad suavizada con media exponencial de ventana temporal corta; el valor exacto del parámetro se fijará con grabaciones reales y quedará documentado aquí.
- Pausas: no acumular distancia ni tiempo; reiniciar el filtro al reanudar.

### Zonas cardíacas (Fase 5)

- % de FC máxima, reserva cardíaca (Karvonen: `FCreposo + %·(FCmáx − FCreposo)`) o umbral introducido por el usuario.
- Una FC máxima estimada por edad es una aproximación poblacional, no una medición individual; la UI lo indicará.

## Matriz de compatibilidad

Se completará **solo con información verificada** en documentación oficial y en dispositivo físico. Ninguna celda se asume.

| Métrica | API pública | En vivo | Tras el entrenamiento | Dispositivos | Verificado |
|---|---|---|---|---|---|
| Tiempo, distancia, FC, energía | HKLiveWorkoutBuilder | por verificar | por verificar | por verificar | ❌ |
| Ritmo | derivado de distancia/velocidad | por verificar | por verificar | por verificar | ❌ |
| Cadencia | por verificar | por verificar | por verificar | por verificar | ❌ |
| Potencia de carrera | `.runningPower` | por verificar | por verificar | por verificar | ❌ |
| Longitud de zancada | `.runningStrideLength` | por verificar | por verificar | por verificar | ❌ |
| Oscilación vertical | `.runningVerticalOscillation` | por verificar | por verificar | por verificar | ❌ |
| Tiempo de contacto | `.runningGroundContactTime` | por verificar | por verificar | por verificar | ❌ |
| Elevación / desnivel | CoreLocation / metadatos | por verificar | por verificar | por verificar | ❌ |
