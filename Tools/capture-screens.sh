#!/usr/bin/env bash
# Regenera las capturas de pantalla del repo: corre el UI test de iOS
# (CenitUITests/CenitScreenshotTests) y copia los PNGs a docs/fixtures/.
#
# Quien las consume es el muro de estados: Tools/build-appmap.py toma un
# subconjunto (su tabla SHOT_SRC), lo reescala y lo acomoda en docs/appmap/.
# Si agregas un estado que valga la pena ver en el muro, agrégale también su
# entrada en SHOT_SRC — si no, la captura se genera pero nadie la mira.
#
# Uso:
#   ./Tools/capture-screens.sh                 # iPhone 17 Pro Max (por defecto)
#   ./Tools/capture-screens.sh "iPhone 16"     # otro simulador
#
# Requiere: Xcode + un simulador iOS. (El CI no puede correr esto — necesita
# bootear el simulador — por eso es un comando manual.)
#
# El script SIEMPRE reporta, y sale != 0 si algo falló:
#   · qué pruebas fallaron (con su razón), en vez de tragárselas y salir 0;
#   · qué fixtures de docs/ NO se regeneraron en esta corrida (o sea, están viejas).
# Antes, un `|| true` mal puesto dejaba pasar una corrida parcial en silencio y
# las capturas viejas se quedaban sin ningún aviso.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="${1:-iPhone 17 Pro Max}"
DEST="$ROOT/docs/fixtures"
LOG="$(mktemp -t noop-screenmap-XXXXXX).log"

# El simulador que bootea xcodebuild se queda prendido headless (~8 GB de RAM)
# hasta el siguiente reinicio; apágalo al salir, pase lo que pase.
trap 'xcrun simctl shutdown all >/dev/null 2>&1 || true' EXIT

echo "▶︎ Corriendo UI test de screenshots en '$SIM'…"
# GIT_CONFIG=/dev/null evita que un override local de git rompa la resolución de SwiftPM.
# `set +e` + PIPESTATUS: necesitamos el status REAL de xcodebuild, no el del grep que lo filtra
# (un grep sin coincidencias sale 1 y antes se confundía con "todo bien" por culpa del `|| true`).
set +e
GIT_CONFIG=/dev/null xcodebuild test \
  -project "$ROOT/Cenit.xcodeproj" -scheme Cenit \
  -destination "platform=iOS Simulator,name=$SIM" \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 4 \
  -only-testing CenitUITests/CenitScreenshotTests \
  2>&1 | tee "$LOG" | grep -E "Test Case|FIXTURE_WRITTEN|error:"
xcb_status=${PIPESTATUS[0]}
set -e

echo "▶︎ Copiando fixtures a docs/fixtures/…"
mkdir -p "$DEST"
WRITTEN="$(mktemp -t noop-screenmap-written-XXXXXX)"
n=0
while IFS= read -r src; do
  [ -f "$src" ] || continue
  base="$(basename "$src")"
  cp "$src" "$DEST/$base" && n=$((n + 1))
  echo "$base" >> "$WRITTEN"
done < <(grep "^FIXTURE_WRITTEN:" "$LOG" | sed 's/^FIXTURE_WRITTEN: //')
echo "  $n fixtures actualizadas."

# ── Reporte 1: pruebas que fallaron ────────────────────────────────────────────
# xcodebuild imprime una línea por caso: Test Case '-[Suite test_x]' passed/failed (N seconds).
failed_tests="$(grep -E "^Test Case .* failed " "$LOG" | sed -E "s/^Test Case '-\[([^]]*)\]'.*/\1/" || true)"
n_passed="$(grep -cE "^Test Case .* passed " "$LOG" || true)"

if [ -n "$failed_tests" ]; then
  n_failed="$(printf '%s\n' "$failed_tests" | wc -l | tr -d ' ')"
  echo ""
  echo "✗ $n_failed prueba(s) FALLARON (y $n_passed pasaron) — sus pantallas NO se regeneraron:" >&2
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    method="${t##* }"
    echo "    · $method" >&2
    # La primera razón que reportó esa prueba (línea `…swift:NN: error: …`).
    grep -E "error:.*\[$method\]|$method.*error:" "$LOG" | head -2 | sed 's/^/        /' >&2 || true
  done <<< "$failed_tests"
else
  echo "  $n_passed prueba(s) pasaron, ninguna falló."
fi

# ── Reporte 2: fixtures viejas (existen en docs/ pero nadie las escribió hoy) ───
if [ -s "$WRITTEN" ]; then
  stale=""
  for f in "$DEST"/*.png; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    grep -qxF "$base" "$WRITTEN" || stale="$stale $base"
  done
  if [ -n "$stale" ]; then
    echo "" >&2
    echo "⚠︎ Fixtures en docs/fixtures/ que esta corrida NO regeneró (viejas o huérfanas):" >&2
    for s in $stale; do echo "    · $s" >&2; done
    echo "  Si la pantalla ya no existe, borra el PNG; si sí existe, agrégale un caso al test." >&2
  fi
fi

if [ "$n" -eq 0 ]; then
  echo "" >&2
  echo "✗ No se capturó ninguna fixture — revisa el log: $LOG" >&2
  exit 1
fi

if [ "$xcb_status" -ne 0 ]; then
  echo "" >&2
  echo "✗ La corrida terminó con fallas (xcodebuild status $xcb_status). Log: $LOG" >&2
  echo "  Las fixtures de las pruebas que SÍ pasaron ya se copiaron; las demás siguen viejas." >&2
  exit "$xcb_status"
fi

echo "✓ Listo. Para rehacer el muro de estados: python3 Tools/build-appmap.py"
echo "  Luego commitea los cambios en docs/fixtures/ y docs/appmap/."
