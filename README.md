# HÅLSYN

**HEALTH IN MOTION** — *Know your body. Understand your health. Improve your life.*

Plataforma nativa de salud, bienestar y rendimiento para **iPhone** y **Apple Watch**, construida con Swift, SwiftUI y HealthKit.

> Estado: **Fase 3 — HÄLSA**. Lee Apple Health (solo lectura) en iPhone y Apple Watch o funciona en **modo demo** identificado, y calcula una puntuación diaria de bienestar transparente ([HEALTH_SCORE](Documentation/HEALTH_SCORE.md)) con historial y resumen nocturno. El registro de entrenamientos llega en la Fase 4. Ver [ROADMAP](Documentation/ROADMAP.md).

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

## Probar la app

Necesitas un **Mac con Xcode 16 o posterior** (gratis en la Mac App Store).

### 1. Descargar y abrir

```sh
git clone https://github.com/juanmarcosmoreno-arch/HALSYN.git
cd HALSYN
git checkout claude/halsyn-phase-1
open Halsyn.xcodeproj
```

### 2. Simulador (sin firmar nada)

Esquema **Halsyn** → elige un simulador de iPhone → ⌘R. En el onboarding elige **Explorar con datos demo**, o añade datos en la app **Salud** del simulador y pulsa **Conectar Apple Health**. El esquema **HalsynWatch** abre el reloj en un simulador de Apple Watch.

### 3. Tu iPhone y tu Apple Watch

1. Xcode › Settings › Accounts: añade tu Apple ID.
2. Proyecto **Halsyn** › Build Settings › *User-Defined*: cambia `HALSYN_BUNDLE_ID` por uno propio (p. ej. `com.tunombre.halsyn`). El del reloj y los tests se ajustan solos.
3. Targets **Halsyn** y **HalsynWatch** › Signing & Capabilities › elige tu **Team**.
4. Conecta el iPhone por cable, actívale el **Modo desarrollador** (Ajustes › Privacidad y seguridad) y pulsa ⌘R. La app del reloj se instala con la del iPhone si el Apple Watch está emparejado.
5. Si iOS dice que el desarrollador no es de confianza: Ajustes › General › VPN y gestión de dispositivos › confía en tu cuenta.

Con un Apple ID gratuito la app caduca a los 7 días y puede haber limitaciones con capacidades como HealthKit; con el Apple Developer Program (de pago) no hay caducidad y se puede distribuir por TestFlight.

### Tests

⌘U en el esquema **Halsyn**, o sin Xcode: `cd Packages/HalsynKit && swift test`.

Si modificas `project.yml`: `brew install xcodegen && xcodegen generate`.

## Documentación

- [ARCHITECTURE](Documentation/ARCHITECTURE.md) · [DESIGN_SYSTEM](Documentation/DESIGN_SYSTEM.md) · [HEALTHKIT_INTEGRATION](Documentation/HEALTHKIT_INTEGRATION.md)
- [RUNNING_ENGINE](Documentation/RUNNING_ENGINE.md) · [SCIENTIFIC_REFERENCES](Documentation/SCIENTIFIC_REFERENCES.md) · [PRIVACY](Documentation/PRIVACY.md)
- [TESTING](Documentation/TESTING.md) · [ROADMAP](Documentation/ROADMAP.md) · [LOCALIZATION](Documentation/LOCALIZATION.md) · [HEALTH_SCORE](Documentation/HEALTH_SCORE.md)

## Aviso

HÅLSYN ofrece estimaciones de bienestar y rendimiento. No es un dispositivo médico, no diagnostica enfermedades y no sustituye la valoración de un profesional sanitario.
