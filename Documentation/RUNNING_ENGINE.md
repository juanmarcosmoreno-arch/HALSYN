# Motor de running (SPRING)

## Estado actual (Fase 4)

Las carreras se registran de verdad en el Apple Watch, sin depender del iPhone.

```
Reloj
 ├─ WorkoutManager (HalsynWatch/Workout)
 │   ├─ HKWorkoutSession + HKLiveWorkoutBuilder  → estado, FC, distancia, energía; guarda el entrenamiento
 │   ├─ CLLocationManager (.fitness, máxima precisión) → puntos GPS
 │   └─ HKWorkoutRouteBuilder                     → ruta (solo puntos fiables)
 └─ RunSessionTracker (HalsynCore, puro y testeado)
     ├─ WorkoutStateMachine   idle → preparing → running ⇄ paused → stopping → ended
     ├─ ActiveTimer           tiempo activo sin pausas
     ├─ GPSDistanceAccumulator
     ├─ PaceEstimator
     └─ LapTracker
```

### Flujo

1. SPRING en el reloj → **Carrera al aire libre** o **Carrera en cinta** (sin GPS). También se puede iniciar desde el iPhone (SPRING › Correr con Apple Watch → `HKHealthStore.startWatchApp`).
2. Se piden permisos (escritura: entrenamiento, ruta, energía, distancia; lectura: FC, energía, distancia, entrenamientos) y ubicación.
3. Pantallas deslizando en horizontal: **controles** (pausa/reanudar, vuelta, terminar) · **métricas** (perfil Easy Run) · **vueltas**.
4. **Terminar** pide confirmación: *Guardar en Apple Health* o *Descartar*. Al guardar se escribe el entrenamiento y su ruta **una sola vez** (el iPhone nunca escribe entrenamientos, así no hay duplicados).
5. Resumen: distancia, tiempo, ritmo medio, FC media y máxima registrada, vueltas.

Hápticos: inicio, pausa, vuelta automática, vuelta manual y guardado. La pantalla siempre activa reduce la frecuencia de actualización a 1 s. `WKBackgroundModes = workout-processing` mantiene la sesión con la muñeca bajada.

**Recuperación**: si watchOS cierra la app durante una carrera, al relanzarla `handleActiveWorkoutRecovery` → `recoverActiveWorkoutSession` recupera la sesión (tiempo, FC y distancia de HealthKit siguen intactos). Los puntos de ruta anteriores al cierre se pierden; la ruta continúa desde ese momento.

### Distancia

- **Fuente principal**: la distancia de `HKLiveWorkoutBuilder` (`distanceWalkingRunning`), que Apple calcula combinando GPS y acelerómetro. Es la que se guarda en Apple Health, así que la que muestra la app coincide con la de Salud.
- **Respaldo**: si HealthKit no entrega distancia, se usa `GPSDistanceAccumulator`:
  1. Descarta puntos con precisión horizontal peor de 25 m.
  2. Descarta saltos imposibles (> 12,5 m/s).
  3. **Anti-deriva**: solo suma cuando el desplazamiento desde el último ancla supera la precisión declarada (entre 3 y 15 m). Parado con el GPS "bailando" ±4 m suma menos de 15 m en 5 minutos (test).
  4. Tras una pausa o 30 s sin señal no une el hueco con una recta.
  5. Desnivel positivo con histéresis de 3 m y precisión vertical ≤ 10 m.
- Validación con trazas sintéticas: recta limpia (±5 m en 2,1 km), ruido de 3 m (< 1,5 %), pista de 400 m con ruido (< 2 % en 4 vueltas), pérdida de señal, puntos inválidos.

### Ritmo

| Ritmo | Cálculo |
|---|---|
| Actual (el que se muestra) | Distancia recorrida en una **ventana móvil de 20 s** sobre la misma distancia que se muestra. Responde a un cambio real (6:00 → 4:00 /km) en ≤ 20 s y no oscila con el ruido punto a punto (5:00 /km ± 25 s con ruido de 3 m). |
| Parado | Si la distancia no avanza en 10 s, el ritmo actual se oculta ("--") en lugar de mostrar un valor viejo. |
| Medio | Distancia total / tiempo activo (sin pausas). |
| Vuelta | Distancia y tiempo desde el inicio de la vuelta. |

Tras pausar o reanudar, la ventana se vacía para no mezclar tramos.

### Vueltas

- **Auto Lap** cada 1 km (configurable en el modelo; el ajuste en la app llega con el editor de la Fase 5). El instante exacto de cruce se **interpola** entre las dos actualizaciones de distancia que lo rodean.
- **Vuelta manual** desde los controles.

### Campos sin dato en vivo

Zona cardíaca, cadencia, potencia, ritmo objetivo e intervalo se muestran como "--" hasta que existan sus motores o se verifique su disponibilidad en vivo (Fase 5). No se rellenan con estimaciones.

## Matriz de compatibilidad

Se completará **solo con información verificada** en documentación oficial y en dispositivo físico. Ninguna celda se asume.

| Métrica | API pública | En vivo | Tras el entrenamiento | Dispositivos | Verificado |
|---|---|---|---|---|---|
| Tiempo, distancia, FC, energía | HKLiveWorkoutBuilder | sí (implementado; pendiente de verificar en dispositivo) | sí | Apple Watch con watchOS 10+ | ⏳ |
| Ritmo | derivado de distancia/velocidad | por verificar | por verificar | por verificar | ❌ |
| Cadencia | por verificar | por verificar | por verificar | por verificar | ❌ |
| Potencia de carrera | `.runningPower` | por verificar | por verificar | por verificar | ❌ |
| Longitud de zancada | `.runningStrideLength` | por verificar | por verificar | por verificar | ❌ |
| Oscilación vertical | `.runningVerticalOscillation` | por verificar | por verificar | por verificar | ❌ |
| Tiempo de contacto | `.runningGroundContactTime` | por verificar | por verificar | por verificar | ❌ |
| Elevación / desnivel | CoreLocation / metadatos | por verificar | por verificar | por verificar | ❌ |
