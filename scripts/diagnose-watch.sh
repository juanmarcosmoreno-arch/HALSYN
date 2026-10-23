#!/bin/bash
# Diagnóstico de instalación en Apple Watch.
#
# Uso (desde la carpeta HALSYN, después de ⌘R en Xcode con tu iPhone):
#   bash scripts/diagnose-watch.sh
#   bash scripts/diagnose-watch.sh "/ruta/a/Stoka.app"   # opcional: compara con una app que sí se instala
#
# Solo lee información (no instala ni cambia nada) y la imprime para copiarla.

set -u
section() { printf '\n===== %s =====\n' "$1"; }

section "Xcode"
xcodebuild -version 2>/dev/null | head -2

section "Dispositivos que ve Xcode (CoreDevice)"
xcrun devicectl list devices 2>&1 | grep -v -i "simulator" | head -20

section "Certificados de firma"
security find-identity -v -p codesigning 2>/dev/null | head -5

describe_app() {
    local app="$1" label="$2"
    section "$label: $app"
    if [ ! -d "$app" ]; then
        echo "No existe."
        return
    fi
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist" 2>/dev/null | sed 's/^/Bundle ID: /'
    /usr/libexec/PlistBuddy -c "Print :WKCompanionAppBundleIdentifier" "$app/Info.plist" 2>/dev/null | sed 's/^/WKCompanionAppBundleIdentifier: /'
    /usr/libexec/PlistBuddy -c "Print :WKRunsIndependentlyOfCompanionApp" "$app/Info.plist" 2>/dev/null | sed 's/^/WKRunsIndependentlyOfCompanionApp: /'
    /usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$app/Info.plist" 2>/dev/null | sed 's/^/MinimumOSVersion: /'
    codesign -dvv "$app" 2>&1 | grep -E "Authority=|TeamIdentifier|Signature=" | head -4
    echo "-- Entitlements:"
    codesign -d --entitlements :- "$app" 2>/dev/null | plutil -p - 2>/dev/null | head -15
    if [ -f "$app/embedded.mobileprovision" ]; then
        local plist
        plist=$(mktemp)
        security cms -D -i "$app/embedded.mobileprovision" > "$plist" 2>/dev/null
        echo "-- Perfil: $(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist" 2>/dev/null)"
        echo "   Equipo: $(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$plist" 2>/dev/null)"
        echo "   Caduca: $(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$plist" 2>/dev/null)"
        echo "   Dispositivos incluidos:"
        /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$plist" 2>/dev/null | grep -v -E '^\s*(Array \{|\})' | sed 's/^ */     /'
        rm -f "$plist"
    else
        echo "-- SIN embedded.mobileprovision (no está firmada para dispositivos)"
    fi
}

section "Compilación más reciente de HÅLSYN para dispositivo"
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 6 -type d -path "*Debug-iphoneos/Halsyn.app" 2>/dev/null | xargs -I{} stat -f "%m {}" {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "$APP" ]; then
    echo "No encontré Halsyn.app para dispositivo. Compila con ⌘R eligiendo tu iPhone y vuelve a ejecutar."
else
    echo "$APP"
    echo "-- Contenido de Watch/:"
    ls "$APP/Watch" 2>&1
    describe_app "$APP" "App de iPhone"
    describe_app "$APP/Watch/HalsynWatch.app" "App de reloj embebida"
fi

if [ $# -ge 1 ]; then
    REF="$1"
    describe_app "$REF" "Referencia (app que sí funciona)"
    if [ -d "$REF/Watch" ]; then
        for watchApp in "$REF"/Watch/*.app; do
            describe_app "$watchApp" "Reloj de la referencia"
        done
    fi
fi

section "Fin"
echo "Copia todo desde 'Xcode' hasta aquí y pégalo en el chat."
