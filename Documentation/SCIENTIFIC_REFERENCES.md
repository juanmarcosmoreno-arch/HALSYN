# Referencias científicas

## Política

- **No se inventan datasets ni percentiles.** Ninguna comparación poblacional se mostrará sin una fuente verificada con los campos de la plantilla.
- Se distinguen valores medidos directamente (laboratorio) de estimaciones del Apple Watch; no se comparan entre sí sin advertirlo.
- Las puntuaciones de HÅLSYN son estimaciones de bienestar, no medidas clínicamente validadas.

## Estado (Fase 1)

No hay ningún dataset incorporado. Los valores del modo demo son sintéticos, plausibles para un adulto activo, y **no** constituyen referencias.

## Fuentes a investigar (Fase 8)

- NHANES (CDC) — encuestas poblacionales de EE. UU.
- FRIEND Registry — capacidad cardiorrespiratoria medida en prueba de esfuerzo.
- Literatura indexada en PubMed sobre FC en reposo y HRV por edad y sexo.
- Recomendaciones oficiales de actividad física y sueño (OMS y sociedades científicas).

Cada candidata se revisará por: población, método de medición, compatibilidad con la estimación del Apple Watch y licencia de uso.

## Plantilla de dataset

```yaml
id:
fuente:            # publicación u organismo
referencia:        # DOI / PMID / URL oficial
año:
población:
país:
rango_edad:
sexo:
método_medición:   # p. ej. prueba de esfuerzo con análisis de gases
unidad:
tamaño_muestra:
percentiles:       # por grupo de edad/sexo
limitaciones:
compatible_con_apple_watch:   # sí / con advertencia / no, y por qué
```

## Edad fisiológica

Arquitectura prevista, pero **sin fórmula** hasta disponer de un modelo validado aplicable a los datos del Apple Watch. Mientras tanto solo se mostrarán indicadores y percentiles.
