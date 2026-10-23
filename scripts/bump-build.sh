#!/usr/bin/env bash
# Sube el número de compilación (CFBundleVersion) en 1 en cada cambio, para
# saber qué versión está instalada (Perfil › Desarrollo › Versión) y poder
# subir a TestFlight. Uso: scripts/bump-build.sh [versión, p. ej. 0.9.0]
set -euo pipefail
cd "$(dirname "$0")/.."
build=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml)
next=$((build + 1))
sed -i.bak "s/CURRENT_PROJECT_VERSION: \"$build\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
if [ $# -gt 0 ]; then
  sed -i.bak "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$1\"/" project.yml
fi
rm -f project.yml.bak
echo "Versión $(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml) ($next)"
