# Privacidad

## Principios

- **Local-first**: los datos de salud se procesan en el dispositivo.
- **Mínima recopilación**: solo se piden los tipos de HealthKit que usa cada módulo.
- **Consentimiento explícito** y explicado antes de cada permiso.
- Sin venta de datos, sin publicidad basada en salud, sin SDKs de analítica publicitaria.
- Sin envío automático de métricas a servicios de IA.
- El usuario controla y puede borrar los datos propios de HÅLSYN.

## Estado (Fase 1)

- La app no lee ni escribe Apple Health, no hace peticiones de red y no incluye dependencias de terceros.
- Solo guarda en `UserDefaults` la apariencia y el sistema de unidades.
- Los datos mostrados son sintéticos y se generan en el dispositivo.

## Antes de publicar (Fase 10)

- Revisar las App Review Guidelines (sección de salud e investigación) y las condiciones de uso de HealthKit: no usar datos de HealthKit para publicidad ni compartirlos con terceros sin consentimiento, no guardar datos de salud en iCloud fuera de los mecanismos permitidos.
- Preparar política de privacidad pública y etiquetas de privacidad de App Store coherentes con el código.
- Añadir `PrivacyInfo.xcprivacy` declarando las APIs de motivo obligatorio que se usen (p. ej. `UserDefaults`).
- Revisar normativa aplicable (RGPD: datos de salud como categoría especial).
