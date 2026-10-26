# Hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Inspección del entorno | ✅ |
| 1 | Fundaciones: proyecto, targets iOS/watchOS, design system, navegación, pantallas, modo demo, 9 idiomas | ✅ compila y pasa tests en CI (macOS) |
| 2 | HealthKit real: permisos, pasos, FC, FC reposo, HRV, sueño, entrenamientos, ausencia de datos, onboarding | ✅ compila y pasa tests en CI · ⏳ prueba en dispositivo |
| 3 | HÄLSA: HealthScoreEngine provisional, dashboard real, historial, explicaciones, resumen nocturno | ✅ compila y pasa tests en CI |
| 4 | SPRING core: sesión de entrenamiento, GPS, ritmo, distancia, FC en vivo, pausa, guardado | ✅ compila y pasa tests en CI · ⏳ prueba corriendo con el reloj |
| 5 | SPRING pro: editor de pantallas, zonas, alertas hápticas, vueltas, intervalos, mapas | ✅ compila y pasa tests en CI · ⏳ prueba corriendo con el reloj |
| 6 | VILA: sueño, RecoveryEngine, tendencias | ✅ compila y pasa tests en CI · ⏳ prueba con datos reales |
| 7 | INSIKT: análisis longitudinal, patrones con requisitos mínimos de datos | ✅ compila y pasa tests en CI · ⏳ revisión con datos reales |
| 8 | Referencias por edad: datasets verificados, ReferencePercentileEngine | ✅ tests del núcleo · ⏳ CI de la app · ⏳ revisión de licencia (FRIEND) |
| 9 | MÅL: creación de objetivos, planificación, recordatorios | ✅ tests del núcleo · ⏳ prueba en dispositivo |
| 10 | Preparación comercial: privacidad, accesibilidad, rendimiento, batería, revisión nativa de traducciones, App Store, TestFlight | |

## Fase 1 — entregado

- Proyecto Xcode (XcodeGen) con app iPhone, app Apple Watch independiente embebida y target de tests.
- Paquete `HalsynKit` (Core / Design / HealthKit).
- Design system con tokens claro/oscuro verificados (WCAG AA), 13 componentes requeridos + logotipo, símbolo, distintivo demo.
- Pantallas: HÄLSA, SPRING (+ detalle de carrera), VILA, INSIKT, MÅL, Perfil (+ vocabulario y galería), detalle de métrica. Reloj: inicio, Mi estado, SPRING (vista previa de pantallas), Recuperación, Resumen diario.
- Iconos y splash generados desde un SVG maestro.
- 9 idiomas en la fase 1; desde 0.9.0 (34), 3: es, en, sv, con String Catalogs generados y formatos regionales.

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

## Fase 5 — entregado

- **Ajustes de carrera** en el iPhone (SPRING › Ajustes de carrera), enviados al reloj con WatchConnectivity (`updateApplicationContext`); el reloj guarda la última copia y funciona sin el iPhone. Solo viajan preferencias, nunca datos de salud.
- **Editor de pantallas**: hasta 4 pantallas, 1/2/3/4/6 campos, sin campos repetidos (al elegir uno ya usado se intercambian), vista previa con valores de ejemplo.
- **Vuelta automática** configurable (desactivada, 400 m, 1 km, 1 milla, 5 km).
- **Zonas cardíacas**: 5 zonas (50/60/70/80/90 %) por % de FC máx. o reserva (Karvonen). La FC máxima la introduce el usuario o es la más alta registrada en sus carreras; nunca se estima por la edad. Sin FC máxima no hay zonas ("--").
- **Alertas hápticas** de ritmo y de zona: avisan tras 10 s fuera de rango, repiten cada 60 s y avisan al volver (con histéresis en el ritmo).
- **Intervalos**: planes con calentamiento, n × (serie + recuperación) por tiempo, distancia o "hasta pulsar Vuelta", ritmo objetivo opcional por serie, vuelta a la calma. Página propia en el reloj con lo que falta y hápticos en cada cambio.
- **Mapa** en el reloj (ruta recorrida y posición) y en el detalle del iPhone.
- **Detalle de carrera**: ruta, parciales por km/milla calculados desde la ruta, gráfico de FC y tiempo en zonas.
- Potencia de carrera en vivo si el reloj la entrega; si no, "--".

## Pendientes conocidos de la Fase 5

- **Probar en un Apple Watch real**: hápticos, intervalos, mapa, sincronización de ajustes, potencia.
- Cadencia en vivo: sin mostrar hasta verificar su disponibilidad en dispositivo.
- Tras un cierre inesperado de la app, la carrera recuperada sigue como libre (el plan de intervalos no se conserva).
- Los parciales se calculan desde la ruta GPS: pueden diferir ligeramente de la distancia total de Apple Health.
- Los permisos piden ahora también leer la ruta de los entrenamientos: quien ya conectó Apple Health debe aceptarlo (Perfil › Gestionar permisos o al volver a conectar).

## Fase 6 — entregado

- `RecoveryEngine` 0.1-provisional: HRV y FC en reposo frente a tu media de 28 días, sueño de anoche y esfuerzo de los últimos 3 días; explica cada componente y la confianza ([RECOVERY](RECOVERY.md)). Mismo motor en demo y Apple Health; también en el reloj.
- Sueño por noche: fases (solo de la fuente dominante), hipnograma, tiempo dormido, horarios, regularidad y objetivo de sueño personal.
- VILA completa: recuperación con desglose y tendencia, anoche, horarios de 14 noches, sueño frente al objetivo, HRV y FC en reposo frente a tu rango habitual.
- Gráficas rediseñadas en toda la app ([DESIGN_SYSTEM](DESIGN_SYSTEM.md#gráficas)) y capturas automáticas en CI (claro y oscuro) que ya detectaron un fallo real.
- Animación de apertura en claro y oscuro (completa, breve o desactivada).

## Pendientes conocidos de la Fase 6

- Calibrar `RecoveryEngine` con datos reales; revisar nombres de fases del sueño con hablantes nativos.
- Las capturas de CI se adjuntan como artefacto; no se comparan píxeles.

## Fase 7 — entregado

- `InsightEngine` 0.1 ([INSIGHTS](INSIGHTS.md)): qué cambió (4 semanas frente a las 4 anteriores, t de Welch), patrones entre métricas (lista cerrada de 6 pares plausibles, Spearman), semana tipo (ANOVA) y récords. Corrección por comparaciones múltiples (Benjamini–Hochberg), tamaño de efecto mínimo y requisitos de datos visibles.
- `Stats` propio verificado con valores de tablas estadísticas.
- INSIKT rediseñado con gráficas de antes/después, comparación de grupos y semana tipo; lenguaje de observación, nunca de causa.
- Firma: equipo y bundle ID en `Config/Halsyn.xcconfig` para que `git pull` no deje el reloj sin firmar.

## Pendientes conocidos de la Fase 7

- Recomendaciones accionables sobre las observaciones.
- Revisión nativa de las frases con días de la semana en pt-BR, it, sv y da.

## Fase 8 — entregado

- `ReferenceLibrary` con dos tablas verificadas ([SCIENTIFIC_REFERENCES](SCIENTIFIC_REFERENCES.md)): VO₂ máx. (FRIEND 2015) y FC en reposo (NHANES 1999–2008). La HRV no se compara (no hay tabla comparable).
- `ReferencePercentileEngine`: interpolación lineal entre percentiles publicados, sin extrapolar fuera de la tabla.
- Perfil: fecha de nacimiento y sexo (a mano o desde Salud), solo en el dispositivo.
- Tarjeta "Tu grupo de edad" en el detalle de VO₂ máx. y FC en reposo y en INSIKT: percentil aproximado, barra con la mitad central del grupo, mediana y tu valor; fuente, población, método y limitaciones siempre visibles.

## Pendientes conocidos de la Fase 8

- Revisión legal del uso de la tabla FRIEND 2015 en una app comercial; valorar la tabla de 2022 (CC BY-NC-ND).
- Fuentes nórdicas/europeas por edad si se verifican.

## Fase 9 — entregado

- MÅL: siete tipos de objetivo (pasos, ejercicio, distancia, distancia corriendo, carreras, sueño medio, energía activa), por día, semana o mes; ritmo (adelantado, en camino, por detrás), historial y racha.
- Progresión opcional de distancia semanal corriendo (+10 % por semana hasta el objetivo final).
- Recordatorios locales que solo dicen el objetivo, nunca datos de salud.
- Widgets de iPhone y complicaciones del reloj (HÄLSA, VILA y objetivo; acceso rápido a SPRING) con datos compartidos por App Group.
- Reloj: gráfico de ritmo y pulso en vivo durante la carrera, indicador de zona y mapa sin gestos (no bloquea pasar de página ni parar).

## CYKEL (bici) — 0.10.0

- **Pestaña CYKEL** en el iPhone:
  - salida en bici desde el reloj (exterior o rodillo);
  - estadísticas de semana, mes y año con velocidad, desnivel y potencia;
  - récords: más larga, más rápida de 20 km o más y más desnivel;
  - historial.
- **Potencia y FTP**:
  - FTP propio, de Apple Health o estimado (95 % de los mejores 20 min);
  - 7 zonas de Coggan en vatios;
  - en cada salida: potencia media, ponderada, mejores 20 min, intensidad, carga y tiempo en zonas.
- **Detalle de la salida**:
  - ruta;
  - perfil de altitud y velocidad;
  - parciales de 5 km;
  - FC por zonas.
- **Reloj**:
  - CYKEL en la pantalla de inicio;
  - páginas de velocidad y pulso, y de potencia (3 s, con zona si hay FTP), cadencia, velocidad media y desnivel;
  - vuelta automática cada 5 km con aviso de voz.
  - Medidores de potencia y sensores de cadencia y velocidad emparejados con el reloj.
  - Los permisos de bici se piden la primera vez que se sale en bici.
- **HÄLSA**: tarjeta con la última salida.
- Las salidas de otras apps o del app Entreno que estén en Salud también cuentan.

- **Zonas cardíacas propias de bici** (0.10.0 (43)): opcionales, con FC máxima de las salidas. Las usan el reloj y el detalle; sin ellas, las de SPRING.
- **Carga de entrenamiento** (0.10.0 (43)), en SPRING y CYKEL:
  - TRIMP de Banister por pulso (correr, caminar y bici) o TSS con potencia (bici);
  - últimos 7 días frente a la media de las 4 semanas anteriores;
  - 12 semanas por deporte;
  - forma física (42 días), fatiga (7 días) y frescura.

## Pendientes conocidos de CYKEL
- Objetivos de distancia en bici en MÅL y salidas en el resumen semanal de INSIKT.
- Verificar en dispositivo la lectura en vivo de potencia, cadencia y velocidad con distintos sensores.
