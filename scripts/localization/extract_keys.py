#!/usr/bin/env python3
"""Extrae las cadenas de interfaz (claves en español) del código Swift.

Heurística: literales de cadena con texto natural en las apps, el design system
y los modelos de HalsynCore. Las interpolaciones `\\(x)` se convierten en el
especificador que usa SwiftUI (`%lld` para enteros conocidos, `%@` para el resto).
Las cadenas que no son de interfaz se excluyen en IGNORE.

Uso: python3 scripts/localization/extract_keys.py > Localization/source-keys.json
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = [
    ROOT / "Apps",
    ROOT / "Packages/HalsynKit/Sources/HalsynDesign",
    ROOT / "Packages/HalsynKit/Sources/HalsynCore",
]
# Interpolaciones que son enteros (SwiftUI usa %lld para Int).
INT_INTERPOLATIONS = {"phase", "streak", "weeks", "history.filter(\\.isCompleted).count", "history.count", "have", "need", "days", "lap.index", "split.index", "index + 1", "count", "number", "slot + 1", "Int(max)", "Int(distance)", "Int(distance / 1000)", "Int(latestResting)", "runSettings.intervalPlans.count", "time.hours", "time.minutes", "step.rawValue + 1", "Step.allCases.count", "fromAge", "toAge", "age", "subject.age", "percentile", "lower", "comparison.count"}
# Literales que no son texto de interfaz o no deben traducirse.
IGNORE = {
    "HÅLSYN", "Halsyn", "HEALTH IN MOTION", "Know your body. Understand your health. Improve your life.",
    "HÄLSA", "SPRING", "VILA", "INSIKT", "MÅL", "PULS", "SÖMN", "STEG", "KRAFT", "BALANS", "FORM", "TID",
    "FART", "RÖRELSE", "Easy Run", "Intervals", "Race", "EASY RUN", "Apple Health", "DEMO", "—", "--", "·",
    "%d:%02d", "%d:%02d:%02d", "#%02X%02X%02X", "ml/kg·min", "CFBundleShortVersionString", "CFBundleVersion",
    "MARCA", "TOKENS", "COMPONENTES", "WATCH", "VACÍO · CARGA", "PULS · SÖMN · STEG", "HRV", "SpO₂", "VO₂ máx.",
    "easy-run", "intervals", "race", "Apple Health · %@", "0.1-provisional", "HealthScoreEngine", "RecoveryEngine", "RecoveryEngine %@", "InsightEngine", "± %@ min", "%@ → %@", "intro-dark", "intro-light", "profile-photo.jpg", "HalsynMark", ".watchkitapp", ".watchkitapp.widgets", ".widgets", "H", "HalsynRun", "HalsynStatus", "group.%@", "group.", "halsyn://halsa", "halsyn://spring", "Apple Watch", "HealthScoreEngine %@", "RecoveryEngine %@", "± %@ min", "%@ → %@",
    "plan-%@", "screen-%@", "6x400", "5x1k", "8x1min", "6 × 400 m", "5 × 1 km", "8 × 1 min", "<Z1",
    "friend-2015-treadmill", "nhanes-1999-2008-pulse", "P%@", "mL/kg/min", "Kaminsky LA, Arena R, Myers J. Reference Standards for Cardiorespiratory Fitness Measured With Cardiopulmonary Exercise Testing: Data From the Fitness Registry and the Importance of Exercise National Database. Mayo Clin Proc. 2015;90(11):1515–1523.", "Ostchega Y, Porter KS, Hughes J, Dillon CF, Nwankwo T. Resting pulse rate reference data for children, adolescents, and adults: United States, 1999–2008. National Health Statistics Reports no. 41. NCHS; 2011.",
    "km", "mi", "/km", "/mi", "m", "ms", "h", "min", "kcal", "W", "%", "Z", "Resp.",
}
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
INTERP = re.compile(r'\\\((.*?)\)(?=[^)]*$|[^)])')

def to_key(literal: str) -> str:
    out, i = "", 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[j], 0)
                j += 1
            expr = literal[i + 2:j - 1]
            out += "%lld" if expr in INT_INTERPOLATIONS else "%@"
            i = j
        else:
            out += literal[i]
            i += 1
    return out.replace('\\"', '"')

def natural(text: str) -> bool:
    if text in IGNORE or not re.search(r"[A-Za-zÁÉÍÓÚÑáéíóúñü]", text):
        return False
    if re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)+", text):          # SF Symbols
        return False
    if re.fullmatch(r"[a-z][A-Za-z0-9]*", text) and text not in {"lpm", "rpm", "ppm"}:  # identificadores
        return False
    if text.startswith(("halsyn.", "com.", "#", "http", "file:", "data:")):
        return False
    return True

keys = {}
for base in SOURCES:
    for path in sorted(base.rglob("*.swift")):
        for line in path.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith("//") or "#Preview" in stripped or "#expect" in stripped:
                continue
            if "Calendar.current" in stripped or "format:" in stripped and "String(format" in stripped:
                continue
            for match in STRING.finditer(line):
                literal = match.group(1)
                key = to_key(literal)
                # Claves que solo son interpolaciones/símbolos ("%@ %@", "%@ / %@ %@") no se traducen.
                if natural(re.sub(r"%(lld|@)", "", key).strip(" /·()")):
                    keys.setdefault(key, str(path.relative_to(ROOT)))
# Textos de permisos de Info.plist (se traducen en InfoPlist.xcstrings).
for match in re.finditer(r"NS(?:Health\w+|LocationWhenInUse)UsageDescription: (.+)", (ROOT / "project.yml").read_text()):
    keys.setdefault(match.group(1).strip(), "project.yml (Info.plist)")
json.dump(keys, sys.stdout, ensure_ascii=False, indent=1, sort_keys=True)
