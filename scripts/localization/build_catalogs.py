#!/usr/bin/env python3
"""Genera los String Catalogs de Xcode a partir de las traducciones.

Fuente de verdad:
  Localization/source-keys.json          claves en español (extract_keys.py)
  Localization/translations/<idioma>.json  clave → traducción

Salida (no editar a mano; volver a ejecutar este script):
  Apps/HalsyniOS/Resources/Localizable.xcstrings
  Apps/HalsyniOS/Resources/InfoPlist.xcstrings
  Apps/HalsynWatch/Resources/Localizable.xcstrings
  Apps/HalsynWatch/Resources/InfoPlist.xcstrings

Uso: python3 scripts/localization/build_catalogs.py
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LANGUAGES = ["en", "pt-BR", "fr", "it", "sv", "da", "zh-Hans", "hi"]
SOURCE = "es"
SPEC = re.compile(r"%(?:\d+\$)?(@|lld)")

source_keys = json.loads((ROOT / "Localization/source-keys.json").read_text())
translations = {lang: json.loads((ROOT / f"Localization/translations/{lang}.json").read_text()) for lang in LANGUAGES}

errors = []
for lang, table in translations.items():
    missing = set(source_keys) - set(table)
    if missing:
        errors.append(f"{lang}: faltan {len(missing)} claves, p. ej. {sorted(missing)[:3]}")
    for key, value in table.items():
        if not value.strip():
            errors.append(f"{lang}: vacía «{key}»")
        if sorted(SPEC.findall(key)) != sorted(SPEC.findall(value)):
            errors.append(f"{lang}: especificadores distintos en «{key}» → «{value}»")
if errors:
    sys.exit("\n".join(errors))

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def entry(key, source_value=None):
    localizations = {SOURCE: unit(source_value)} if source_value else {}
    for lang in LANGUAGES:
        localizations[lang] = unit(translations[lang][key])
    return {"extractionState": "manual", "localizations": localizations}

def write(path, strings):
    catalog = {"sourceLanguage": SOURCE, "strings": dict(sorted(strings.items())), "version": "1.0"}
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print("✓", path.relative_to(ROOT), f"({len(strings)} cadenas × {len(LANGUAGES) + 1} idiomas)")

ui_keys = {k: v for k, v in source_keys.items() if not v.startswith("project.yml")}
info_values = [k for k, v in source_keys.items() if v.startswith("project.yml")]

project = (ROOT / "project.yml").read_text()
for target, folder in [("Halsyn", "HalsyniOS"), ("HalsynWatch", "HalsynWatch")]:
    resources = ROOT / f"Apps/{folder}/Resources"
    write(resources / "Localizable.xcstrings", {k: entry(k) for k in ui_keys})
    section = project.split(f"\n  {target}:\n", 1)[1].split("\n  Halsyn", 1)[0]
    info = {}
    for plist_key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription", "NSLocationWhenInUseUsageDescription"):
        match = re.search(rf"{plist_key}: (.+)", section)
        if not match:
            continue
        value = match.group(1).strip()
        assert value in info_values, value
        info[plist_key] = entry(value, source_value=value)
        info[plist_key]["extractionState"] = "extracted_with_value"
    write(resources / "InfoPlist.xcstrings", info)

# Extensiones de widgets: mismas cadenas de interfaz (sin textos de permisos).
for folder in ("HalsynWidgets", "HalsynWatchWidgets"):
    resources = ROOT / f"Apps/{folder}/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    write(resources / "Localizable.xcstrings", {k: entry(k) for k in ui_keys})
