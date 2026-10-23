# Arquitectura

## Principios

1. **Separación estricta**: sensores · persistencia · lógica fisiológica · presentación · sincronización · modelos científicos.
2. **Dependencias hacia dentro**: las apps dependen de `HalsynKit`; `HalsynCore` no depende de nada salvo Foundation.
3. **Inyección por protocolos**: las vistas solo conocen `HealthDataProviding`. Demo, HealthKit y mocks son intercambiables.
4. **Origen explícito**: todo dato lleva `DataOrigin` (`.demo`, `.healthKit`, `.derived`). La UI siempre lo muestra.
5. **Ausencia ≠ valor**: `MetricAvailability` distingue `noData`, `notAuthorized` y `unsupported`; `MetricDisplay` garantiza que nunca se muestren como cero.

## Capas

```
┌─────────────── Apps ────────────────┐
│ HalsyniOS            HalsynWatch    │  SwiftUI, navegación, estado de app
└──────┬──────────────────────┬───────┘
       │                      │
┌──────▼──────────── HalsynKit ───────▼───────────────────────┐
│ HalsynDesign   tokens → Color, componentes, símbolo         │
│ HalsynHealthKit  adaptadores HealthKit (Fase 2+)            │
│ HalsynCore     modelos, protocolos, unidades, demo, motores │
└─────────────────────────────────────────────────────────────┘
```

| Módulo | Depende de | Plataformas | Se prueba en |
|---|---|---|---|
| HalsynCore | Foundation | iOS, watchOS, macOS, Linux | `swift test` (Linux y macOS) |
| HalsynDesign | HalsynCore, SwiftUI, Charts | iOS, watchOS, macOS | Previews, compilación en CI macOS |
| HalsynHealthKit | HalsynCore, HealthKit | iOS, watchOS | Fase 2 (mocks + dispositivo) |

Los archivos de HalsynDesign y HalsynHealthKit están envueltos en `#if canImport(...)`, de modo que el paquete completo compila y se prueba en Linux.

## Navegación

- **iPhone**: `TabView` con HÄLSA · SPRING · INSIKT · PERFIL. VILA y MÅL se abren desde HÄLSA (tarjetas) e INSIKT (enlaces), sin sobrecargar la barra.
- **Apple Watch**: `NavigationStack` con estado del día y accesos a SPRING (primero, mínimo número de toques), Mi estado, Recuperación y Resumen diario.

## Estado

- `AppModel` (`@Observable`, `@MainActor`): pestaña seleccionada y proveedor de datos.
- Preferencias ligeras (`apariencia`, `unidades`) en `@AppStorage`.
- **SwiftData** se introducirá cuando haya datos propios que persistir (perfiles de pantalla, objetivos, cachés de motores — Fases 5, 6 y 9). HealthKit seguirá siendo la fuente de los datos fisiológicos.

## Estructura de carpetas (desviaciones respecto a la propuesta inicial)

- `Shared/Models`, `Utilities`, `Localization` → `Packages/HalsynKit/Sources/HalsynCore` (compartido por las dos apps y testeable sin Xcode).
- `Shared/DesignSystem` → `HalsynDesign`.
- `Services/HealthKit` → `HalsynHealthKit`. `Services/Workout`, `Location`, `Persistence`, `Synchronization` y `Engines/*` se añadirán como nuevos módulos o carpetas del paquete en sus fases.
- `Features/` vive dentro de cada app, porque las pantallas del reloj y del iPhone son distintas.

## Decisiones

| Decisión | Motivo |
|---|---|
| XcodeGen (`project.yml`) | Proyecto declarativo, sin conflictos de merge en `.pbxproj`; el `.xcodeproj` generado se incluye para abrirlo directamente. |
| App de reloj de un solo target (watchOS 10+) | Modelo actual de Apple; `WKRunsIndependentlyOfCompanionApp = true` para correr sin iPhone. |
| iOS 17 / watchOS 10 mínimos | `@Observable`, SwiftData, `onChange` de dos parámetros, `containerBackground` en watchOS. |
| Swift 5 language mode en apps | Reduce fricción inicial; migrar a Swift 6 (concurrencia estricta) en Fase 10. El núcleo ya compila sin avisos con Swift 6.3. |
| Swift Testing en HalsynKit, XCTest en la app | Swift Testing funciona en Linux y macOS; XCTest para el host app. |
