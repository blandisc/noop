#!/usr/bin/env bash
# capture-appmap.sh — El "un comando" para regenerar el mapa de estados (docs/appmap):
# corre el harness en el simulador → captura los PNG REALES del código → los reescala a
# shots/ → reconstruye el canvas HTML. (Rescatado/mejorado de la sesión paralela.)
#
#   Tools/capture-appmap.sh                       # los estados de Hoy (por defecto)
#   Tools/capture-appmap.sh test_today_primed …   # tests específicos
#   SIM_NAME="iPhone 16" Tools/capture-appmap.sh  # otro simulador
#
# Nota: el sim UI-test corre HEADLESS aquí (iOS 26.x) — NO necesita una terminal real
# (la vieja advertencia de "Pseudo Terminal Setup Error" quedó obsoleta).
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
STAGING="scratch-appmap-staging"
LOG="$(mktemp -t capture-appmap).log"

# Tests a correr (default: todos los estados de Hoy). Cada uno escribe hoy su PNG crudo.
if [ "$#" -gt 0 ]; then TESTS=("$@"); else
  TESTS=(test_today_empty test_today_calibrating test_today_downloading test_today_insufficient \
         test_today_primed test_today_balanced test_today_strained test_today_rundown); fi
ONLY=(); for t in "${TESTS[@]}"; do ONLY+=(-only-testing "CenitUITests/CenitScreenshotTests/$t"); done

echo "▸ Regenerando proyecto…"
GIT_CONFIG=/dev/null xcodegen generate >/dev/null

# FER-924: capturas deterministas — Reduce Motion del SISTEMA (congela todo el movimiento
# repeatForever de forma uniforme) + status bar canónico (9:41, batería llena, wifi).
xcrun simctl boot "$SIM_NAME" >/dev/null 2>&1 || true
xcrun simctl spawn "$SIM_NAME" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true >/dev/null 2>&1 || true
xcrun simctl status_bar "$SIM_NAME" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi \
  >/dev/null 2>&1 || echo "  (aviso: no se pudo fijar el status bar — sigue con el reloj real)"

echo "▸ Corriendo harness en '$SIM_NAME' (${#TESTS[@]} estados; tarda unos minutos)…"
set +e
GIT_CONFIG=/dev/null xcodebuild test \
  -project Cenit.xcodeproj -scheme Cenit \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  CODE_SIGNING_ALLOWED=NO -jobs 4 "${ONLY[@]}" > "$LOG" 2>&1
RC=$?
set -e
[ "$RC" -ne 0 ] && grep -q "FIXTURE_WRITTEN" "$LOG" || true

echo "▸ Recolectando PNG crudos → $STAGING/"
mkdir -p "$STAGING"; N=0
while IFS= read -r src; do
  [ -f "$src" ] || continue
  cp -f "$src" "$STAGING/"; N=$((N+1))
done < <(grep -o 'FIXTURE_WRITTEN: .*\.png' "$LOG" | sed 's/^FIXTURE_WRITTEN: //')
echo "  $N PNG recolectados."
[ "$N" -eq 0 ] && { echo "✗ Ningún PNG (RC=$RC). Log: $LOG"; exit 1; }

echo "▸ Reescalando a shots/ y reconstruyendo el canvas…"
python3 -c "import sys; sys.path.insert(0,'Tools'); import importlib.util as u; \
s=u.spec_from_file_location('ba','Tools/build-appmap.py'); m=u.module_from_spec(s); s.loader.exec_module(m); \
m.sync_shots('$STAGING'); m.build_served()"

echo "✓ Listo → abre docs/appmap/index.html (o sirve con: cd docs/appmap && python3 -m http.server)"
echo "  Apaga el simulador cuando termines: xcrun simctl shutdown all"
