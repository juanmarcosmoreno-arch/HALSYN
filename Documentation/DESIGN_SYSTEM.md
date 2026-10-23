# Design system

Diseño escandinavo premium: minimalista, orgánico, científico sin parecer clínico. Código en `Packages/HalsynKit/Sources/HalsynDesign`. La galería en la app (**Perfil → Galería del design system**) muestra todos los componentes en el modo activo.

## Marca

- Nombre: **HÅLSYN** (siempre con Å). Identificadores técnicos: `Halsyn`.
- Símbolo: **Å-persona** — cabeza/anillo separado, lóbulo crema, pierna en verde profundo, torso translúcido y pierna menta.
- Referencia aprobada: `Resources/Brand/reference/halsyn-brand-reference.png`.

> ⚠️ El vector actual (`Resources/Brand/halsyn-symbol.svg` y `HalsynSymbolGeometry`) es una **reconstrucción aproximada** de la referencia, no el original. Debe sustituirse por el vector definitivo del diseñador (SVG/PDF). Ambos archivos comparten la misma geometría: al recibir el vector final, actualizar los dos y ejecutar `node scripts/render-brand-assets.js`.

| Pieza | Implementación |
|---|---|
| Símbolo color / monocromo | `HalsynSymbol(style: .color / .monochrome(color))` (Canvas vectorial) |
| Logotipo horizontal, vertical, compacto | `HalsynLogo(.horizontal / .vertical / .compact / .symbol)` |
| Wordmark | `HalsynWordmark` (SF Pro Light, tracking amplio) |
| Icono iPhone / Watch | `Apps/*/Resources/Assets.xcassets/AppIcon.appiconset` (1024 px, generado) |
| Icono alternativo fondo blanco | `Resources/Brand/exports/halsyn-icon-alt-white-1024.png` |
| Splash | `UILaunchScreen` con `LaunchBackground` (claro/oscuro) + `LaunchSymbol` |
| Pendiente | Iconos alternativos seleccionables, variantes oscura/tintada de iOS 18, complicaciones (Fase 10 / WidgetKit) |

## Color

Los valores viven una sola vez en `HalsynCore/Brand/HalsynPalette.swift`; las vistas usan **tokens semánticos** (`.halsynPrimaryText`, `.halsynAccent`…), nunca hexadecimales.

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| background | #F7F8F5 | #081B1A | Fondo de pantalla |
| surface | #FFFFFF | #103330 | Tarjetas |
| primaryText | #0E2D2A | #E8F6F1 | Texto principal |
| secondaryText | #5A6E6A | #9DBDB4 | Texto secundario |
| accent | #1FB99A | #1ED1A6 | Anillos, gráficos, rellenos |
| accentText | #0D7A64 | #5FECCF | Texto/glifos de acento |
| accentSoft | #A7E5C9 | #072B26 | Fondos suaves, pistas |
| positive / caution / alert | #0D7A64 / #9A6200 / #B3261E | #5FECCF / #F2C14E / #FF8A80 | Estados (siempre con icono + texto) |

**Accesibilidad verificada por tests**: todos los tokens de texto alcanzan WCAG AA (≥ 4,5:1) sobre `background` y `surface` en ambos modos. El turquesa de marca #1FB99A **no** llega a 4,5:1 sobre blanco, por eso existe `accentText` (#0D7A64, derivado, no forma parte de la referencia).

watchOS usa siempre la variante oscura.

## Tipografía

SF Pro del sistema basada en estilos de texto (Dynamic Type): `.halsynLargeTitle`, `.halsynTitle`, `.halsynHeadline`, `.halsynBody`, `.halsynCaption`, `.halsynEyebrow`, `.halsynMetricValue` (dígitos monoespaciados). Los números de entrenamiento usan SF Pro Rounded semibold.

## Componentes

| Componente | Descripción |
|---|---|
| `HalsynCard` | Superficie con esquinas continuas, borde fino y sombra mínima |
| `HalsynMetric` | Valor + unidad + título; `nil` → "—" |
| `HalsynMetricTile` | Tesela con icono y estado de disponibilidad |
| `HalsynScoreRing` | Anillo con gradiente angular; el extremo termina en un círculo (eco de la cabeza del símbolo). Respeta *Reduce Motion* |
| `HalsynTrendChart` | Swift Charts, línea o barras, media discontinua, eje X adaptado al periodo |
| `HalsynSectionHeader` | Título + etiqueta sueca + acción opcional |
| `HalsynPrimaryButton` | Cápsula con gradiente de marca, objetivo táctil ≥ 44 pt |
| `HalsynStatusIndicator` | Icono + texto (nunca solo color) |
| `HalsynProgressBar` | Progreso redondeado |
| `HalsynEmptyState` / `HalsynLoadingState` | Estados sin datos y de carga |
| `HalsynDemoBadge` | Distintivo obligatorio para datos sintéticos |
| `HalsynWatchMetric` | Métrica compacta del reloj |
| `HalsynWorkoutField` / `HalsynWorkoutScreen` | Campo y pantalla de entrenamiento (1, 2, 3, 4 o 6 campos) según `WorkoutScreenProfile` |
| `HalsynBackdrop` | Formas orgánicas decorativas (ocultas a VoiceOver) |

## Reglas

- Sin glassmorphism que perjudique la lectura; en running, contraste por encima de la decoración.
- Las animaciones respetan `accessibilityReduceMotion`.
- Todo dato demo lleva `HalsynDemoBadge` o `DataOriginFootnote`.
