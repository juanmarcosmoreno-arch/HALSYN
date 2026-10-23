# Hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Inspección del entorno | ✅ |
| 1 | Fundaciones: proyecto, targets iOS/watchOS, design system, navegación, pantallas, modo demo, 9 idiomas | ✅ compila y pasa tests en CI (macOS) |
| 2 | HealthKit real: permisos, pasos, FC, FC reposo, HRV, sueño, entrenamientos, ausencia de datos, onboarding | ✅ compila y pasa tests en CI · ⏳ prueba en dispositivo |
| 3 | HÄLSA: HealthScoreEngine provisional, dashboard real, historial, explicaciones, resumen nocturno | ✅ compila y pasa tests en CI |
| 4 | SPRING core: sesión de entrenamiento, GPS, ritmo, distancia, FC en vivo, pausa, guardado | ✅ compila y pasa tests en CI · ⏳ prueba corriendo con el reloj |
| 5 | SPRING pro: editor de pantallas, zonas, alertas hápticas, vueltas, intervalos, mapas | |
| 6 | VILA: sueño, RecoveryEngine, tendencias | |
| 7 | INSIKT: análisis longitudinal, patrones con requisitos mínimos de datos | |
| 8 | Referencias por edad: datasets verificados, ReferencePercentileEngine | |
| 9 | MÅL: creación de objetivos, planificación, recordatorios | |
| 10 | Preparación comercial: privacidad, accesibilidad, rendimiento, batería, revisión nativa de traducciones, App Store, TestFlight | |

## Fase 1 — entregado

- Proyecto Xcode (XcodeGen) con app iPhone, app Apple Watch independiente embebida y target de tests.
- Paquete `HalsynKit` (Core / Design / HealthKit).
- Design system con tokens claro/oscuro verificados (WCAG AA), 13 componentes requeridos + logotipo, símbolo, distintivo demo.
- Pantallas: HÄLSA, SPRING (+ detalle de carrera), VILA, INSIKT, MÅL, Perfil (+ vocabulario y galería), detalle de métrica. Reloj: inicio, Mi estado, SPRING (vista previa de pantallas), Recuperación, Resumen diario.
- Iconos y splash generados desde un SVG maestro.
- 9 idiomas (es, en, pt-BR, fr, it, sv, da, zh-Hans, hi) con String Catalogs generados y formatos regionales.

## Pendientes conocidos de la Fase 1

- El símbolo Å-persona es una aproximación vectorial: falta el vector definitivo del diseñador.
- Traducciones (8 idiomas) generadas con IA: requieren revisión nativa antes de publicar.

## Fase 2 — entregado

- `LiveHealthDataProvider` (HalsynCore) sobre el protocolo `HealthStoreClient`: ventanas diarias, sueño por noche sin dobles conteos, último valor con su fecha real, estados distintos para sin datos / bloqueado / error / no disponible.
- `HKHealthStoreClient` (HalsynHealthKit): consultas async de estadísticas, muestras, sueño y carreras; observadores de cambios. Solo lectura.
- Onboarding de 7 pasos (presentación, Apple Health, objetivos, unidades, privacidad, permisos, primera lectura).
- Fuente de datos persistente (demo / Apple Health) en iPhone y, por separado, en Apple Watch; recarga automática.
- Perfil: conectar, gestionar permisos, volver a demo, repetir la introducción.

## Pendientes conocidos de la Fase 2

- Probar con datos reales en iPhone y Apple Watch físicos (CI solo compila y prueba con mocks).
- La recuperación en modo Apple Health aparece como "—" hasta la Fase 6.

## Fase 3 — entregado

- `HealthScoreEngine` 0.1-provisional: 5 dimensiones, pesos configurables, comparación con la media personal, cobertura mínima, confianza y factores explicables ([HEALTH_SCORE](HEALTH_SCORE.md)).
- Misma puntuación en demo y con Apple Health; nunca se inventa si falta cobertura.
- HÄLSA: puntuación con factores principales, desglose, historial (calendario de 5 semanas + tendencia) y resumen del día.
- Resumen nocturno con notificación opcional sin datos de salud en el aviso.
- INSIKT: tendencia de la puntuación diaria.

## Pendientes conocidos de la Fase 3

- Pesos y umbrales sin calibrar con datos reales; revisar tras uso en dispositivo.
- Sin caché: el historial recalcula a partir de HealthKit en cada carga (rápido con 5 series; se revisará con SwiftData si hace falta).

## Fase 4 — entregado

- Carreras reales en el Apple Watch (exterior con GPS y cinta), sin depender del iPhone; inicio también desde el iPhone.
- Pausa, reanudar, vueltas automáticas (1 km) y manuales, terminar con confirmación (guardar o descartar), recuperación tras cierre.
- Distancia de HealthKit con respaldo GPS filtrado; ritmo actual suavizado (20 s), medio y de vuelta; FC en vivo, media y máxima.
- Ruta guardada en Apple Health con los puntos fiables.
- Motor puro (`RunSessionTracker`) con 21 tests sobre trazas GPS sintéticas ([RUNNING_ENGINE](RUNNING_ENGINE.md)).

## Pendientes conocidos de la Fase 4

- **Probar en un Apple Watch real corriendo**: precisión de distancia y ritmo, batería, comportamiento con la muñeca bajada y sin iPhone.
- Las pantallas configurables, zonas, alertas, intervalos y mapas llegan en la Fase 5.
