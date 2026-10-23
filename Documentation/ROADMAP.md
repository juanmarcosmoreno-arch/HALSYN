# Hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Inspección del entorno | ✅ |
| 1 | Fundaciones: proyecto, targets iOS/watchOS, design system, navegación, pantallas, modo demo, 9 idiomas | ✅ compila y pasa tests en CI (macOS) |
| 2 | HealthKit real: permisos, pasos, FC, FC reposo, HRV, sueño, entrenamientos, ausencia de datos, onboarding | ✅ compila y pasa tests en CI · ⏳ prueba en dispositivo |
| 3 | HÄLSA: HealthScoreEngine provisional, dashboard real, historial, explicaciones | ⏳ siguiente |
| 4 | SPRING core: sesión de entrenamiento, GPS, ritmo, distancia, FC en vivo, pausa, guardado | prioridad muy alta |
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
- Puntuación y recuperación en modo Apple Health aparecen como "—" hasta las Fases 3 y 6.
