#!/usr/bin/env bash
# iterate-shot.sh — El loop de iteración visual de UN estado (FER-922):
#   edita el código → `Tools/iterate-shot.sh test_today_primed` → build incremental +
#   ese único test → captura → DIFF vs baseline → compuesto [ANTES|DESPUÉS|DIFF] + stats + tiempos.
#
#   Tools/iterate-shot.sh <test> --baseline   # fija el "antes" (capture sin diff)
#   Tools/iterate-shot.sh <test>              # itera: captura el "después" y diffea
#
# El estado vive en scratch-iterate/<test>/ (baseline.png, current.png, diff.png).
# Requiere: harness CenitScreenshotTests (el test escribe FIXTURE_WRITTEN: *.png).
set -euo pipefail
cd "$(dirname "$0")/.."

TEST="${1:?uso: iterate-shot.sh <test_today_xxx> [--baseline]}"
MODE="${2:-iterate}"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
DIR="scratch-iterate/$TEST"
LOG="$(mktemp -t iterate-shot).log"
mkdir -p "$DIR"

T0=$SECONDS
# xcodegen SIEMPRE (~3s): un proyecto stale tras cambiar de rama rompe el build con
# «Build input file cannot be found»; regenerar con contenido idéntico no invalida el incremental.
GIT_CONFIG=/dev/null xcodegen generate >/dev/null
T_GEN=$((SECONDS - T0))

# FER-924: capturas deterministas.
xcrun simctl boot "$SIM_NAME" >/dev/null 2>&1 || true
# (a) Reduce Motion a nivel SISTEMA — SwiftUI lo lee del trait en cada frontera UIKit, así que
#     congela TODO el movimiento repeatForever (chevron, punto de la tab, latidos, spinner) de forma
#     uniforme. Un override por-vista NO basta (el trait se re-inyecta en TabView/hosting).
xcrun simctl spawn "$SIM_NAME" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true >/dev/null 2>&1 || true
# (b) Status bar canónico (9:41, batería llena, wifi) — el reloj real metía ruido al diff.
xcrun simctl status_bar "$SIM_NAME" override --time "9:41" \
  --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi \
  >/dev/null 2>&1 || echo "  (aviso: no se pudo fijar el status bar — sigue con el reloj real)"

echo "▸ Build incremental + $TEST en '$SIM_NAME'…"
T1=$SECONDS
set +e
GIT_CONFIG=/dev/null xcodebuild test \
  -project Cenit.xcodeproj -scheme Cenit \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  CODE_SIGNING_ALLOWED=NO -jobs 4 \
  -only-testing "CenitUITests/CenitScreenshotTests/$TEST" > "$LOG" 2>&1
RC=$?
set -e
T_BUILD=$((SECONDS - T1))

# Recolectar el frame 1 del estado (today_<estado>.png — sin sufijo _2/_3/_4 de scroll).
SHOT=$(grep -o 'FIXTURE_WRITTEN: .*\.png' "$LOG" | sed 's/^FIXTURE_WRITTEN: //' \
       | grep -vE '_[0-9]+\.png$' | head -1)
[ -z "${SHOT:-}" ] && { echo "✗ Sin captura (RC=$RC). Log: $LOG"; exit 1; }

if [ "$MODE" = "--baseline" ]; then
  cp -f "$SHOT" "$DIR/baseline.png"
  echo "✓ Baseline fijado: $DIR/baseline.png"
  echo "⏱  proyecto ${T_GEN}s · build+test ${T_BUILD}s · TOTAL $((SECONDS - T0))s"
  exit 0
fi

[ -f "$DIR/baseline.png" ] || { echo "✗ No hay baseline — corre primero: Tools/iterate-shot.sh $TEST --baseline"; exit 1; }
cp -f "$SHOT" "$DIR/current.png"

echo "▸ Diff vs baseline…"
T2=$SECONDS
set +e
python3 Tools/diff-shot.py "$DIR/baseline.png" "$DIR/current.png" -o "$DIR/diff.png"
DRC=$?
set -e
T_DIFF=$((SECONDS - T2))

echo "⏱  proyecto ${T_GEN}s · build+test ${T_BUILD}s · diff ${T_DIFF}s · TOTAL $((SECONDS - T0))s"
case $DRC in
  0) echo "→ Compuesto: $DIR/diff.png" ;;
  2) echo "→ Sin cambios visuales (¿el edit compiló pero no afecta este estado?)" ;;
  *) echo "✗ diff-shot falló (rc=$DRC)"; exit $DRC ;;
esac
