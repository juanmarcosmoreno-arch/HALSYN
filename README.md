# HÅLSYN

**HEALTH IN MOTION** — *Know your body. Understand your health. Improve your life.*

Plataforma nativa de salud, bienestar y rendimiento para **iPhone** y **Apple Watch**, construida con Swift, SwiftUI y HealthKit.

> Estado: **Fase 1 — Fundaciones**. La app funciona en **modo demo** con datos sintéticos claramente identificados. Todavía no lee Apple Health (Fase 2) ni registra entrenamientos (Fase 4). Ver [ROADMAP](Documentation/ROADMAP.md).

## Módulos

| Marca | Significado | Qué hace |
|---|---|---|
| **HÄLSA** | Salud | Estado fisiológico diario, puntuación, indicadores |
| **SPRING** | Correr | Running avanzado en Apple Watch |
| **VILA** | Descanso | Sueño, recuperación, HRV, FC en reposo |
| **INSIKT** | Comprensión | Tendencias y análisis longitudinal |
| **MÅL** | Objetivo | Metas de salud y entrenamiento |

## Idiomas

Español, inglés, portugués (Brasil), francés, italiano, sueco, danés, chino simplificado e hindi. El usuario puede cambiar el idioma solo para HÅLSYN en **Ajustes › HÅLSYN › Idioma**. Ver [LOCALIZATION](Documentation/LOCALIZATION.md).

## Estructura

```
HALSYN/
├── project.yml                 # Fuente de verdad del proyecto (XcodeGen)
├── Halsyn.xcodeproj            # Generado desde project.yml (incluido en el repo)
├── Apps/
│   ├── HalsyniOS/              # App de iPhone (App, Features/, Shared/, Resources/)
│   └── HalsynWatch/            # App de Apple Watch independiente (watchOS 10+)
├── Packages/HalsynKit/         # Paquete Swift compartido
│   ├── Sources/HalsynCore      # Modelos, protocolos, unidades, demo (solo Foundation)
│   ├── Sources/HalsynDesign    # Design system SwiftUI y símbolo Å-persona
│   ├── Sources/HalsynHealthKit # Catálogo de tipos de HealthKit
│   └── Tests/HalsynCoreTests   # Tests (Swift Testing)
├── Tests/HalsyniOSTests        # Tests de la capa de app (XCTest)
├── Resources/Brand/            # SVG maestro, referencia aprobada, exportaciones
├── Localization/               # Claves en español y traducciones (fuente de los .xcstrings)
├── scripts/                    # Iconos y catálogos de idiomas (generación reproducible)
└── Documentation/
```

## Abrir en Xcode

Requisitos: macOS con **Xcode 16 o posterior** (SDK iOS 17+ / watchOS 10+).

1. `open Halsyn.xcodeproj`
2. Target **Halsyn** → *Signing & Capabilities* → elige tu **Team** (repite en **HalsynWatch**). Los bundle IDs son `com.halsyn.app` y `com.halsyn.app.watchkitapp`; cámbialos si ya existen en tu cuenta.
3. Esquema **Halsyn** → un simulador de iPhone → ⌘R. El esquema **HalsynWatch** lanza el reloj en un simulador de Apple Watch.
4. Tests: ⌘U en el esquema **Halsyn** (ejecuta `HalsyniOSTests` y `HalsynCoreTests`).

Si modificas `project.yml`: `brew install xcodegen && xcodegen generate`.

Tests del núcleo sin Xcode (macOS o Linux con Swift 5.9+):

```sh
cd Packages/HalsynKit && swift test
```

## Documentación

- [ARCHITECTURE](Documentation/ARCHITECTURE.md) · [DESIGN_SYSTEM](Documentation/DESIGN_SYSTEM.md) · [HEALTHKIT_INTEGRATION](Documentation/HEALTHKIT_INTEGRATION.md)
- [RUNNING_ENGINE](Documentation/RUNNING_ENGINE.md) · [SCIENTIFIC_REFERENCES](Documentation/SCIENTIFIC_REFERENCES.md) · [PRIVACY](Documentation/PRIVACY.md)
- [TESTING](Documentation/TESTING.md) · [ROADMAP](Documentation/ROADMAP.md) · [LOCALIZATION](Documentation/LOCALIZATION.md)

## Aviso

HÅLSYN ofrece estimaciones de bienestar y rendimiento. No es un dispositivo médico, no diagnostica enfermedades y no sustituye la valoración de un profesional sanitario.
