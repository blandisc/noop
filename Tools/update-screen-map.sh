#!/usr/bin/env bash
# Regenera los screenshots del mapa de pantallas (docs/screen-map.html).
# Corre el UI test de iOS, copia los PNGs a docs/fixtures/ y actualiza la fecha
# del toolbar del mapa. Es el "un solo comando" para mantener el mapa al día.
#
# Uso:
#   ./Tools/update-screen-map.sh                 # iPhone 17 Pro Max (por defecto)
#   ./Tools/update-screen-map.sh "iPhone 16"     # otro simulador
#
# Requiere: Xcode + un simulador iOS. (El CI no puede correr esto — necesita
# bootear el simulador — por eso es un comando manual.)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="${1:-iPhone 17 Pro Max}"
DEST="$ROOT/docs/fixtures"
LOG="$(mktemp -t noop-screenmap-XXXXXX).log"

echo "▶︎ Corriendo UI test de screenshots en '$SIM'…"
# GIT_CONFIG=/dev/null evita que un override local de git rompa la resolución de SwiftPM.
GIT_CONFIG=/dev/null xcodebuild test \
  -project "$ROOT/Strand.xcodeproj" -scheme NOOPiOS \
  -destination "platform=iOS Simulator,name=$SIM" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing NOOPiOSUITests/NOOPScreenshotTests \
  2>&1 | tee "$LOG" | grep -E "Test Case|FIXTURE_WRITTEN|error:" || true

echo "▶︎ Copiando fixtures a docs/fixtures/…"
mkdir -p "$DEST"
n=0
while IFS= read -r src; do
  [ -f "$src" ] || continue
  cp "$src" "$DEST/$(basename "$src")" && n=$((n + 1))
done < <(grep "^FIXTURE_WRITTEN:" "$LOG" | sed 's/^FIXTURE_WRITTEN: //')
echo "  $n fixtures actualizadas."

if [ "$n" -eq 0 ]; then
  echo "✗ No se capturó ninguna fixture — revisa el log: $LOG" >&2
  exit 1
fi

# Sube la fecha 'Actualizado' del toolbar del mapa.
TODAY="$(date +%F)"
MAP="$ROOT/docs/screen-map.html"
if grep -q 'tb-updated' "$MAP" 2>/dev/null; then
  /usr/bin/sed -i '' -E "s#(Actualizado )[0-9]{4}-[0-9]{2}-[0-9]{2}#\1${TODAY}#" "$MAP"
  echo "  Fecha del mapa → $TODAY"
fi

echo "✓ Listo. Ábrelo con doble clic (docs/screen-map.html) y commitea los cambios en docs/."
