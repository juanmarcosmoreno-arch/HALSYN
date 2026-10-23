# Idiomas

HÅLSYN está disponible en **9 idiomas**:

| Código | Idioma | Notas |
|---|---|---|
| `es` | Español | Idioma de desarrollo; las claves son el texto en español |
| `en` | Inglés | |
| `pt-BR` | Portugués (Brasil) | Añadir `pt-PT` si se quiere la variante europea |
| `fr` | Francés | |
| `it` | Italiano | |
| `sv` | Sueco | |
| `da` | Danés | |
| `zh-Hans` | Chino simplificado | |
| `hi` | Hindi | India tiene muchos idiomas oficiales; se eligió el hindi como primero. Añadir bengalí, tamil, telugu, etc. sigue el mismo proceso |

Los nombres de módulo (HÄLSA, SPRING, VILA, INSIKT, MÅL) y el vocabulario sueco (PULS, SÖMN, STEG…) **no se traducen** en ningún idioma: son marca.

## Cómo elige el idioma el usuario

iOS y watchOS usan el idioma del sistema si la app lo admite. Para elegir otro solo para HÅLSYN: **Ajustes › HÅLSYN › Idioma** (la fila *Idioma* de Perfil abre esa pantalla). El reloj sigue el idioma configurado en el iPhone para el Apple Watch.

## Formatos regionales

Números, fechas y separadores siguen la configuración regional (`HalsynFormat.decimal` / `integer` / `distance`): `5,21 km` en español, `5.21 km` en inglés, `8 600` pasos en francés. Ritmo (`4:42`) y duración (`24:36`) usan el formato universal `m:ss`. Las unidades se traducen como claves (`lpm` → `bpm`, `ppm` → `spm`…).

## Flujo de trabajo

```
código Swift ──extract_keys.py──▶ Localization/source-keys.json
                                          │
              Localization/translations/<idioma>.json  (traducciones)
                                          │
                                 build_catalogs.py
                                          ▼
     Apps/*/Resources/Localizable.xcstrings + InfoPlist.xcstrings
```

1. Escribe el texto en español en el código (`Text("…")`, o `String` que la UI muestra con `LocalizedStringKey`).
2. `python3 scripts/localization/extract_keys.py > Localization/source-keys.json`
3. Añade la traducción de cada clave nueva en los 8 archivos de `Localization/translations/`.
4. `python3 scripts/localization/build_catalogs.py` (falla si falta una clave, si una traducción está vacía o si no conserva los `%@` / `%lld`).

CI (job *localization*) comprueba que los pasos 2 y 4 están al día.

### Reglas para el código

- No uses `Text(verbatim:)` ni concatenes cadenas visibles: la frase no podrá traducirse. Usa interpolación dentro de `Text("…")` o `String(localized: "…")`, que genera claves con `%@` / `%lld`.
- No formatees números con `String(format:)` en la interfaz: usa `HalsynFormat`.
- Las cadenas de `HalsynCore` (títulos de métricas, módulos, estados) están en español y la UI las muestra con `LocalizedStringKey(...)`, de modo que se traducen con el catálogo de la app.

## Calidad de las traducciones

Las traducciones iniciales se generaron con IA respetando el glosario anterior. **Antes de publicar deben revisarlas hablantes nativos**, con prioridad para los textos de permisos de salud, los avisos médicos y las etiquetas cortas de la pantalla de entrenamiento (longitud en el reloj).
